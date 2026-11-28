extends RefCounted
class_name WorldCommandTests
## Fixture numbers and permissions are test-only, not gameplay authorization.

class RecordingSync extends WorldSyncAdapter:
	var prepares: int = 0
	var activates: int = 0
	var reject: bool = false
	var activation_fault: bool = false
	var active: Dictionary = {}
	var on_prepare: Callable

	func prepare(previous: Dictionary, candidate: Dictionary, changes: Dictionary) -> Dictionary:
		prepares += 1
		if on_prepare.is_valid():
			on_prepare.call()
		previous.clear()
		return {"ok": not reject, "prepared": {"candidate": candidate, "changes": changes}, "errors": []}

	func activate(prepared: Dictionary) -> bool:
		if activation_fault:
			return false
		activates += 1
		active = prepared.duplicate(true)
		return true


var passed: int = 0
var failed: int = 0


func run() -> Dictionary:
	for scenario: Callable in [_template_and_copy, _space_and_devices, _routes, _atomic_and_retry, _sync_and_identity, _session_integration, _coordinate_representability, _plate_batch_final_position]:
		_check(scenario.call() == true, "scenario completed: " + scenario.get_method())
	return {"passed": passed, "failed": failed}


func _check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		push_error("WORLD TEST FAILED: " + label)


func _rules() -> Dictionary:
	return {
		"parameter_ranges": {
			"camera": {"view_radius": [0.1, 20.0], "fov_angle": [0.1, TAU], "scan_center": [-PI, PI], "scan_half_angle": [0.0, PI], "scan_speed": [0.0, 4.0]},
			"robot": {"view_radius": [0.1, 20.0], "move_speed": [0.1, 4.0]},
		},
		"camera_mount_limits": {"wall": {"half_angle": PI / 2.0}, "ceiling": {"center": 0.0, "half_angle": PI}},
		"camera_per_anchor": 1,
	}


func _camera(cell: Array = [2, 2]) -> Dictionary:
	return {"kind": "camera", "cell": cell, "mount_type": "ceiling", "parameters": {"enabled": true, "view_radius": 5.0, "fov_angle": 1.0, "scan_center": 0.0, "scan_half_angle": 0.5, "scan_speed": 1.0}}


func _plate(cell: Array) -> Dictionary:
	return {"kind": "pressure_plate", "cell": cell, "parameters": {}}


func _fixture() -> Dictionary:
	var terrain: Array = []
	for y: int in 8:
		var row: Array = []
		for x: int in 8:
			row.append("WALL" if x == 0 or y == 0 or x == 7 or y == 7 else "FLOOR")
		terrain.append(row)
	return {
		"template_key": "test_only", "grid_size": [8, 8], "cell_size": 1.0, "origin": [0.0, 0.0],
		"terrain": terrain, "player_spawn": [1.5, 1.5], "device_rules": _rules(),
		"initial_entities": [_camera(), {"kind": "robot", "cell": [1, 3], "parameters": {"view_radius": 4.0, "move_speed": 1.0}, "patrol_path": [[1, 3], [2, 3], [3, 3]]}, _plate([2, 2]), {"kind": "goal", "cell": [5, 5], "parameters": {}}, {"kind": "contact", "cell": [5, 1], "parameters": {}}, {"kind": "exit", "cell": [6, 5], "parameters": {}}],
	}


func _world() -> WorldState:
	return LevelTemplate.from_data(_fixture()).instantiate_world()


func _policy() -> Dictionary:
	var rules: Dictionary = {"commands": {
		"SetMapCell": ["map"], "AddDevice": ["camera", "robot", "pressure_plate", "goal"],
		"RemoveDevice": DeviceRegistry.KINDS.duplicate(), "MoveDevice": DeviceRegistry.KINDS.duplicate(),
		"SetDeviceParameter": ["camera", "robot"], "SetPatrolPath": ["robot"],
	}, "parameters": {"camera": DeviceRegistry.CAMERA_NUMBERS.duplicate() + ["enabled"], "robot": DeviceRegistry.ROBOT_NUMBERS.duplicate()}, "max_commands": 8}
	return {AgentProtocol.SYSTEM_AGENT: rules.duplicate(true), AgentProtocol.PLAYER_ASSISTANT: rules.duplicate(true)}


func _context(request: int = 1, phase: int = SessionPhase.Phase.DISPATCH_PAUSED) -> Dictionary:
	var role: String = AgentProtocol.PLAYER_ASSISTANT if phase == SessionPhase.Phase.CONTACT_PAUSED else AgentProtocol.SYSTEM_AGENT
	var result: Dictionary = AgentProtocol.make_request_context(role, request, 1, 1, 1)
	result["phase"] = phase
	return result


func _batch(commands: Array, expected: Dictionary, revision: int = 0, mode: String = "APPLY") -> WorldCommandBatch:
	return WorldCommandBatch.from_data({"context": AgentProtocol.serialize_context(expected), "source": "contact" if expected.role == AgentProtocol.PLAYER_ASSISTANT else "dispatch", "base_world_revision": revision, "mode": mode, "commands": commands})


func _move(id: int, cell: Array) -> Dictionary:
	return {"type": "MoveDevice", "id": id, "cell": cell}


func _map(cell: Array, kind: String = "WALL") -> Dictionary:
	return {"type": "SetMapCell", "cell": cell, "cell_kind": kind}


func _route(cells: Array) -> Dictionary:
	return {"type": "SetPatrolPath", "robot_id": 2, "cells": cells}


func _parameter(name: String, value: Variant) -> Dictionary:
	return {"type": "SetDeviceParameter", "id": 1, "parameter": name, "value": value}


func _rejected(commands: Array, code: String, initial: WorldState = null) -> void:
	var service := WorldCommandService.new(initial if initial != null else _world(), _policy(), WorldSyncAdapter.new())
	var before: Dictionary = service.get_world_snapshot().to_snapshot()
	var result: WorldCommandResult = service.commit_batch(_batch(commands, _context(), before.world_revision), _context())
	_check(result.status == "REJECTED" and result.errors[0].code == code, "rejection " + code + " for " + str(commands))
	_check(service.get_world_snapshot().to_snapshot() == before, "rejected batch leaves all state unchanged")


func _template_and_copy() -> bool:
	var input: Dictionary = _fixture()
	var template := LevelTemplate.from_data(input)
	input.initial_entities[0].parameters.view_radius = 999
	input.terrain[1][1] = "WALL"
	_check(template.validate().is_empty(), "template owns copied input")
	var world: WorldState = template.instantiate_world()
	_check(world != null and world.registry.to_snapshot().size() == 6, "six entity kinds instantiate")
	_check(world.next_entity_id == 7 and world.registry.get_entity(6).kind == "exit", "world assigns ordered stable IDs")
	var snapshot: Dictionary = world.to_snapshot()
	var copy: WorldState = world.snapshot_copy()
	_check(copy.to_snapshot() == snapshot, "full in-memory roundtrip")
	copy.terrain[2][2] = "WALL"
	copy.device_rules.parameter_ranges.camera.view_radius[1] = 999
	var entity: Dictionary = world.registry.get_entity(1)
	entity["parameters"]["view_radius"] = 999
	snapshot.entities[0].parameters.view_radius = 999
	_check(world.registry.get_entity(1).parameters.view_radius == 5.0 and world.terrain[2][2] == "FLOOR", "nested copies cannot mutate world")
	_check(world.device_rules.parameter_ranges.camera.view_radius[1] == 20.0, "rule copies isolated")
	_check(world.world_to_cell(Vector2(-0.1, 0.5)) == Vector2i(-1, 0), "negative coordinates use floor")
	_check(world.world_to_cell(Vector2(2.0, 2.0)) == Vector2i(2, 2), "cell boundary deterministic")
	_check(world.cell_to_world(Vector2i(2, 3)) == Vector2(2.5, 3.5), "waypoints use cell centers")
	for bad: Variant in ["2", 2.5, null]:
		var data: Dictionary = _fixture()
		data.grid_size[0] = bad
		_check(LevelTemplate.from_data(data).instantiate_world() == null, "malformed dimensions rejected")
	var invalid: Dictionary = world.to_snapshot()
	invalid.entities[1].id = 1
	_check(WorldState.from_snapshot(invalid) == null, "duplicate snapshot ID rejected")
	invalid = world.to_snapshot()
	invalid["next_entity_id"] = 6
	_check(WorldState.from_snapshot(invalid) == null, "snapshot allocator cannot reuse live IDs")
	invalid = world.to_snapshot()
	invalid["player_position"] = [INF, 1.0]
	_check(WorldState.from_snapshot(invalid) == null, "non-finite snapshot rejected")
	invalid = world.to_snapshot()
	invalid["extra_field"] = true
	_check(WorldState.from_snapshot(invalid) == null, "unknown snapshot field rejected")
	var command_data: Dictionary = _batch([_move(3, [3, 2])], _context()).to_data()
	var command_copy: WorldCommandBatch = WorldCommandBatch.from_data(command_data)
	command_data.commands[0].cell[0] = 6
	_check(command_copy.to_data().commands[0].cell == [3, 2], "batch owns its input")
	command_data.commands[0]["extra_field"] = 1
	_check(WorldCommandBatch.from_data(command_data) == null, "unknown command field rejected")
	var offset: Dictionary = _fixture()
	offset["origin"] = [-10.0, 20.0]
	offset["cell_size"] = 2.0
	offset["player_spawn"] = [-7.0, 23.0]
	offset["initial_entities"][0]["parameters"]["view_radius"] = 4.0
	var scaled: WorldState = LevelTemplate.from_data(offset).instantiate_world()
	_check(scaled.cell_to_world(Vector2i(1, 3)) == Vector2(-7.0, 27.0), "origin and scale affect all cell centers")
	_check(scaled.registry.get_entity(2).runtime_state.position == [-7.0, 27.0], "robot initial position uses world conversion")
	var fractional: Dictionary = offset.duplicate(true)
	fractional.initial_entities[0].parameters.view_radius = 5.0
	_check(LevelTemplate.from_data(fractional).instantiate_world() == null, "noninteger cell radius rejected in template")
	var invalid_radius_snapshot: Dictionary = world.to_snapshot()
	invalid_radius_snapshot.entities[0].parameters.view_radius = 5.5
	_check(WorldState.from_snapshot(invalid_radius_snapshot) == null, "noninteger cell radius rejected in snapshot")
	return true


func _space_and_devices() -> bool:
	var world: WorldState = _world()
	_check(not world.get_cell_profile(Vector2i(2, 2)).blocks_movement, "ceiling camera and pad share walkable cell")
	for cell: Vector2i in [Vector2i(0, 1), Vector2i(5, 5), Vector2i(5, 1), Vector2i(6, 5)]:
		var profile: Dictionary = world.get_cell_profile(cell)
		_check(profile.blocks_movement and profile.blocks_vision, "solid blocks both queries")
	_check(world.get_cell_profile(Vector2i(6, 5)).exit_id == 6, "exit contact identity independent of solid volume")
	_rejected([{"type": "AddDevice", "device": _plate([2, 2])}], "OCCUPANCY_CONFLICT")
	_rejected([_move(3, [5, 5])], "OCCUPANCY_CONFLICT")
	_rejected([_move(3, [8, 2])], "INVALID_POSITION")
	_rejected([_map([2, 2])], "INVALID_POSITION")
	_rejected([{"type": "RemoveDevice", "id": 99}], "UNKNOWN_ID")
	_rejected([{"type": "RemoveDevice", "id": 4}], "PERMISSION_DENIED")
	_rejected([_move(5, [4, 1])], "PERMISSION_DENIED")
	_rejected([{"type": "AddDevice", "device": {"kind": "goal", "cell": [4, 4], "parameters": {}}}], "PERMISSION_DENIED")
	_rejected([_move(2, [4, 4])], "PERMISSION_DENIED")
	_rejected([_parameter("view_radius", 999)], "INVALID_PARAMETER")
	_rejected([_parameter("view_radius", 5.5)], "INVALID_PARAMETER")
	var fractional_camera: Dictionary = _camera([4, 4])
	fractional_camera.parameters.view_radius = 5.5
	_rejected([{"type": "AddDevice", "device": fractional_camera}], "INVALID_PARAMETER")
	_rejected([_parameter("view_radius", "5")], "INVALID_PARAMETER")
	_rejected([_parameter("view_radius", INF)], "INVALID_COMMAND")
	_rejected([_parameter("permissions", [])], "PERMISSION_DENIED")
	var camera: Dictionary = _camera([1, 2])
	camera["mount_type"] = "wall"
	camera["wall_side"] = "west"
	var service := WorldCommandService.new(world, _policy(), WorldSyncAdapter.new())
	var result: WorldCommandResult = service.commit_batch(_batch([{"type": "AddDevice", "device": camera}], _context()), _context())
	_check(result.status == "APPLIED" and result.created_ids[0].id == 7, "wall camera added with world ID")
	var current: WorldState = service.get_world_snapshot()
	_rejected([_map([0, 2], "FLOOR")], "INVALID_POSITION", current)
	_rejected([{"type": "MoveDevice", "id": 7, "cell": [3, 2], "mount_type": "wall", "wall_side": "west"}], "INVALID_POSITION", world_with_revision_zero(current))
	camera["parameters"]["scan_center"] = PI
	_rejected([{"type": "AddDevice", "device": camera}], "INVALID_PARAMETER")
	var support_repair := WorldCommandService.new(current, _policy(), WorldSyncAdapter.new())
	var replacement: Dictionary = {"type": "MoveDevice", "id": 7, "cell": [3, 2], "mount_type": "ceiling"}
	_check(support_repair.commit_batch(_batch([_map([0, 2], "FLOOR"), replacement], _context(), 1), _context()).status == "APPLIED", "support removal can be repaired within atomic batch")
	var scan_snapshot: Dictionary = _world().to_snapshot()
	scan_snapshot.entities[0].runtime_state.heading = 0.4
	scan_snapshot.entities[0].runtime_state.scan_direction = -1
	var scan_service := WorldCommandService.new(WorldState.from_snapshot(scan_snapshot), _policy(), WorldSyncAdapter.new())
	_check(scan_service.commit_batch(_batch([_parameter("scan_half_angle", 0.2)], _context()), _context()).status == "APPLIED", "bounded scanner parameter accepted")
	var scanner: Dictionary = scan_service.get_world_snapshot().registry.get_entity(1)
	_check(is_equal_approx(scanner.runtime_state.heading, 0.2) and scanner.runtime_state.scan_direction == -1, "scan interval clamps heading but preserves direction")
	for target: Array in [[1, 1], [1, 3]]:
		var under_actor := WorldCommandService.new(_world(), _policy(), WorldSyncAdapter.new())
		var moved: WorldCommandResult = under_actor.commit_batch(_batch([_move(3, target)], _context()), _context())
		_check(moved.status == "APPLIED", "pad deploys under player or robot")
		_check(under_actor.get_world_snapshot().registry.get_entity(3).runtime_state == {"occupants": [], "baseline_ready": false}, "deployment only invalidates baseline hook")
	return true


func world_with_revision_zero(world: WorldState) -> WorldState:
	var result: WorldState = world.snapshot_copy()
	result.world_revision = 0
	return result


func _routes() -> bool:
	_rejected([_route([])], "INVALID_PATH")
	_rejected([_route([[1, 3], [2, 4]])], "INVALID_PATH")
	_rejected([_route([[1, 3], [3, 3]])], "INVALID_PATH")
	_rejected([_route([[1, 3], [0, 3]])], "INVALID_PATH")
	_rejected([_route([[1, 3], [1, 3]])], "INVALID_PATH")
	_rejected([_route([[4, 3]])], "INVALID_PATH")
	_rejected([_route([[1.0, 3]])], "INVALID_COMMAND")
	var service := WorldCommandService.new(_world(), _policy(), WorldSyncAdapter.new())
	_check(service.commit_batch(_batch([_route([[1, 3]])], _context()), _context()).status == "APPLIED", "single waypoint is valid station")
	var station: Dictionary = service.get_world_snapshot().registry.get_entity(2)
	_check(station.runtime_state.position == [1.5, 3.5] and station.patrol_path.size() == 1, "station does not teleport")
	var snapshot: Dictionary = _world().to_snapshot()
	snapshot.entities[1].runtime_state.position = [1.75, 3.5]
	snapshot.entities[1].runtime_state.progress = 0.25
	var moving: WorldState = WorldState.from_snapshot(snapshot)
	_check(moving != null, "mid-segment state restores")
	_rejected([_route([[1, 3]])], "INVALID_PATH", moving)
	service = WorldCommandService.new(moving, _policy(), WorldSyncAdapter.new())
	var route: Array = [[2, 3], [2, 4], [3, 4]]
	_check(service.commit_batch(_batch([_route(route)], _context()), _context()).status == "APPLIED", "path joins existing segment destination")
	var robot: Dictionary = service.get_world_snapshot().registry.get_entity(2)
	_check(robot.runtime_state.position == [1.75, 3.5], "new route preserves continuous position")
	_check(robot.runtime_state.transition == {"from_cell": [1, 3], "to_cell": [2, 3], "progress": 0.25}, "unfinished segment stored once outside patrol")
	_check(robot.runtime_state.travel_direction == 1 and robot.patrol_path == route, "new ping-pong path needs no endpoint closure")
	var roundtrip: WorldState = service.get_world_snapshot().snapshot_copy()
	_check(roundtrip != null and roundtrip.registry.get_entity(2) == robot, "transition survives deep copy")
	_rejected([_map([1, 3])], "INVALID_PATH", world_with_revision_zero(roundtrip))
	var reverse_snapshot: Dictionary = _world().to_snapshot()
	reverse_snapshot.entities[1].runtime_state.position = [3.25, 3.5]
	reverse_snapshot.entities[1].runtime_state.path_index = 2
	reverse_snapshot.entities[1].runtime_state.progress = 0.25
	reverse_snapshot.entities[1].runtime_state.travel_direction = -1
	var reversing: WorldState = WorldState.from_snapshot(reverse_snapshot)
	_check(reversing != null and reversing.snapshot_copy().to_snapshot() == reverse_snapshot, "return leg preserves ping-pong direction")
	var reversed_service := WorldCommandService.new(reversing, _policy(), WorldSyncAdapter.new())
	_check(reversed_service.commit_batch(_batch([_route([[2, 3]])], _context()), _context()).status == "APPLIED", "return leg can finish segment then station")
	_check(reversed_service.get_world_snapshot().registry.get_entity(2).runtime_state.transition.from_cell == [3, 3], "return leg uses correct segment origin")
	var restricted: Dictionary = _policy()
	restricted[AgentProtocol.SYSTEM_AGENT]["allowed_cells"] = [[1, 3]]
	var restricted_service := WorldCommandService.new(_world(), restricted, WorldSyncAdapter.new())
	var robot_definition: Dictionary = _fixture().initial_entities[1]
	_check(restricted_service.commit_batch(_batch([{"type": "AddDevice", "device": robot_definition}], _context()), _context()).errors[0].code == "PERMISSION_DENIED", "new robot path cannot escape allowed region")
	return true


func _atomic_and_retry() -> bool:
	var sync := RecordingSync.new()
	var service := WorldCommandService.new(_world(), _policy(), sync)
	var before: Dictionary = service.get_world_snapshot().to_snapshot()
	var bad: WorldCommandBatch = _batch([{"type": "AddDevice", "device": _plate([4, 4])}, _move(99, [3, 3])], _context())
	_check(service.commit_batch(bad, _context()).status == "REJECTED", "later failure rejects whole batch")
	_check(service.get_world_snapshot().to_snapshot() == before and sync.prepares == 0, "rollback includes ID and no sync")
	var expected: Dictionary = _context(2)
	var add: WorldCommandBatch = _batch([{"type": "AddDevice", "device": _plate([4, 4])}], expected)
	_check(service.validate_batch(add, expected).status == "VALID", "dry run valid")
	_check(service.validate_batch(add, expected).created_ids.is_empty(), "dry run does not expose reserved IDs")
	_check(service.get_world_snapshot().to_snapshot() == before and sync.prepares == 0, "dry run has no side effects")
	var result: WorldCommandResult = service.commit_batch(add, expected)
	_check(result.status == "APPLIED" and result.created_ids[0].id == 7, "failed candidate did not consume ID")
	result.created_ids[0].id = 900
	var retry: WorldCommandResult = service.commit_batch(add, expected)
	_check(retry.created_ids[0].id == 7 and sync.activates == 1, "retry returns isolated original receipt")
	_check(service.commit_batch(_batch([_move(3, [3, 2])], expected), expected).errors[0].code == "REQUEST_REUSE", "same identity cannot change content")
	var remove_context: Dictionary = _context(3)
	var remove: WorldCommandBatch = _batch([{"type": "RemoveDevice", "id": 7}], remove_context, 1)
	_check(service.commit_batch(remove, remove_context).status == "APPLIED", "remove existing ID")
	_check(service.commit_batch(remove, remove_context).status == "APPLIED" and sync.activates == 2, "remove retry does not execute again")
	_check(service.commit_batch(_batch([{"type": "RemoveDevice", "id": 7}], _context(4), 2), _context(4)).errors[0].code == "UNKNOWN_ID", "fresh removal of absent ID is error")
	var readd: WorldCommandResult = service.commit_batch(_batch([{"type": "AddDevice", "device": _plate([4, 4])}], _context(5), 2), _context(5))
	_check(readd.created_ids[0].id == 8, "deleted IDs are not reused")
	var repaired := WorldCommandService.new(_world(), _policy(), WorldSyncAdapter.new())
	var repair: Array = [_map([2, 3]), _route([[1, 3], [1, 4], [2, 4], [3, 4]])]
	_check(repaired.commit_batch(_batch(repair, _context()), _context()).status == "APPLIED", "final-world validation accepts route repair in same batch")
	_check(repaired.get_world_snapshot().get_cell_profile(Vector2i(2, 3)).blocks_movement, "wall command changes authoritative passage")
	_rejected([_map([2, 3])], "INVALID_PATH")
	var used_snapshot: Dictionary = _world().to_snapshot()
	used_snapshot.entities[2].runtime_state.occupants = [0]
	used_snapshot.entities[2].runtime_state.baseline_ready = true
	used_snapshot.entities[4].runtime_state.used = true
	used_snapshot.entities[0].runtime_state.heading = 0.3
	var no_op_sync := RecordingSync.new()
	var no_op := WorldCommandService.new(WorldState.from_snapshot(used_snapshot), _policy(), no_op_sync)
	_check(no_op.commit_batch(_batch([_move(3, [2, 2]), _parameter("scan_half_angle", 0.5)], _context()), _context()).status == "UNCHANGED", "identical commands do not reset runtime state")
	_check(no_op.get_world_snapshot().to_snapshot() == used_snapshot and no_op_sync.prepares == 0, "no-op preserves used contact and pad/scanner state")
	_check(no_op.commit_batch(_batch([], _context(2), 0, "KEEP_CURRENT"), _context(2)).status == "UNCHANGED" and no_op.get_world_snapshot().registry.get_entity(5).runtime_state.used, "keep current cannot undo contact usage")
	return true


func _sync_and_identity() -> bool:
	var sync := RecordingSync.new()
	sync.reject = true
	var service := WorldCommandService.new(_world(), _policy(), sync)
	var before: Dictionary = service.get_world_snapshot().to_snapshot()
	var expected: Dictionary = _context()
	var batch: WorldCommandBatch = _batch([_move(3, [3, 2])], expected)
	_check(service.commit_batch(batch, expected).errors[0].code == "SYNC_PREPARE_FAILED", "sync failure rejects commit")
	_check(sync.activates == 0 and service.get_world_snapshot().to_snapshot() == before, "failed sync keeps active world")
	sync.reject = false
	expected = _context(2)
	batch = _batch([_move(3, [3, 2])], expected)
	var reentrant: Array = []
	sync.on_prepare = func() -> void: reentrant.append(service.commit_batch(batch, expected).status)
	_check(service.commit_batch(batch, expected).status == "APPLIED", "retry with new request can deploy")
	sync.on_prepare = Callable()
	_check(reentrant == ["REJECTED"] and sync.activates == 1, "sync reentry cannot commit")
	_check(sync.active.candidate.entities[2].cell == [3, 2], "adapter receives full candidate")
	sync.active.candidate.entities[2].cell = [6, 6]
	_check(service.get_world_snapshot().registry.get_entity(3).cell == [3, 2], "adapter cannot mutate authority")
	var last_active: Dictionary = sync.active.duplicate(true)
	sync.reject = true
	_check(service.commit_batch(_batch([_move(3, [4, 2])], _context(3), 1), _context(3)).status == "REJECTED", "later preparation can fail")
	_check(sync.active == last_active and service.get_world_snapshot().registry.get_entity(3).cell == [3, 2], "prepare failure preserves previous activated state")
	sync.reject = false
	var fresh: Dictionary = _context(3)
	fresh["branch_id"] = 2
	_check(service.commit_batch(batch, fresh).errors[0].code == "STALE_BRANCH", "old branch rejected before cached success")
	var stale: WorldCommandBatch = _batch([_move(3, [4, 2])], _context(4), 0)
	_check(service.commit_batch(stale, _context(4)).errors[0].code == "STALE_WORLD", "stale revision rejected")
	for field: String in ["round_id", "guess_cycle_id", "request_id", "role"]:
		var mismatch: Dictionary = expected.duplicate(true)
		mismatch[field] = AgentProtocol.PLAYER_ASSISTANT if field == "role" else 99
		_check(service.commit_batch(batch, mismatch).status == "REJECTED", "context rejects " + field)
	var action: Dictionary = expected.duplicate(true)
	action["phase"] = SessionPhase.Phase.ACTION
	_check(service.commit_batch(batch, action).errors[0].code == "INVALID_PHASE", "action cannot submit even cached request")
	var blocked := WorldCommandService.new(_world(), {}, WorldSyncAdapter.new())
	_check(blocked.commit_batch(_batch([_move(3, [3, 2])], _context()), _context()).status == "REJECTED", "no implicit role permissions")
	var keep: WorldCommandBatch = _batch([], _context(5), 1, "KEEP_CURRENT")
	_check(service.commit_batch(keep, _context(5)).status == "UNCHANGED" and sync.activates == 1, "explicit keep skips sync")
	_check(_batch([], _context()) == null, "empty apply is not implicit keep")
	var faulty_sync := RecordingSync.new()
	faulty_sync.activation_fault = true
	var faulty := WorldCommandService.new(_world(), _policy(), faulty_sync)
	_check(faulty.commit_batch(_batch([_move(3, [3, 2])], _context()), _context()).errors[0].code == "SYNC_ACTIVATION_FAILED", "activation fault cannot report successful commit")
	_check(faulty.get_world_snapshot().world_revision == 0, "activation fault leaves authoritative revision unchanged")
	_check(faulty.commit_batch(_batch([], _context(2), 0, "KEEP_CURRENT"), _context(2)).errors[0].code == "SYNC_ACTIVATION_FAILED", "activation fault locks even explicit keep")
	return true


func _session_integration() -> bool:
	var session := GameSession.new(SessionRules.new(3, 1))
	var sync := RecordingSync.new()
	var service := WorldCommandService.new(_world(), _policy(), sync)
	_check(session.begin_contact(), "contact opens")
	_check(not session.end_contact(), "missing deploy callback cannot advance")
	_check(not session.end_contact(func(_e: Dictionary) -> bool: return true), "plain success boolean cannot advance")
	_check(not session.end_contact(func(e: Dictionary) -> WorldCommandResult: return service.validate_batch(_batch([_move(3, [3, 2])], e), e)), "preview receipt cannot advance")
	_check(not session.end_contact(func(e: Dictionary) -> WorldCommandResult: return service.commit_batch(_batch([_move(3, [5, 5])], e), e)), "invalid deployment stays paused")
	_check(session.get_cycle_snapshot().simulation_tick == 0 and session.get_state_snapshot().phase == SessionPhase.Phase.CONTACT_PAUSED, "failed contact preserves tick and phase")
	session.renew_world_request()
	sync.reject = true
	_check(not session.end_contact(func(e: Dictionary) -> WorldCommandResult: return service.commit_batch(_batch([_move(3, [3, 2])], e), e)), "sync failure keeps contact paused")
	session.renew_world_request()
	sync.reject = false
	_check(session.end_contact(func(e: Dictionary) -> WorldCommandResult: return service.commit_batch(_batch([_move(3, [3, 2])], e), e)), "real service deploy releases contact")
	_check(service.get_world_snapshot().registry.get_entity(3).cell == [3, 2] and session.get_cycle_snapshot().simulation_tick == 0, "world changed before next physics tick")
	for tick: int in [1, 2, 3]:
		_check(session.advance_physics_step(WorldFrame.new(tick, Vector2(1.5, 1.5), false, false)).accepted, "advance to guess")
	var sequence: Array = []
	_check(session.process_report_boundary(func(_b: ReportBoundary) -> void: sequence.append("seal"), func(_b: ReportBoundary) -> void: sequence.append("view")), "report processes without delayed config callback")
	_check(sequence == ["seal", "view"] and sync.activates == 1, "report does not redeploy")
	_check(session.accept_guess_result(session.get_state_snapshot().active_request_context, false), "miss enters dispatch")
	_check(not session.complete_dispatch(), "dispatch missing deployment remains paused")
	_check(session.complete_dispatch(func(e: Dictionary) -> WorldCommandResult: return service.commit_batch(_batch([], e, 1, "KEEP_CURRENT"), e)), "explicit keep completes dispatch")
	_check(session.get_state_snapshot().phase == SessionPhase.Phase.CYCLE_START_PENDING and not session.resume_cycle(false), "snapshot gate remains")
	_check(session.resume_cycle(true), "resume after snapshot confirmation")
	var fault_session := GameSession.new(SessionRules.new(3, 1))
	var fault_sync := RecordingSync.new()
	fault_sync.activation_fault = true
	var fault_service := WorldCommandService.new(_world(), _policy(), fault_sync)
	fault_session.begin_contact()
	_check(not fault_session.end_contact(func(e: Dictionary) -> WorldCommandResult: return fault_service.commit_batch(_batch([_move(3, [3, 2])], e), e)), "activation fault does not release session")
	fault_session.renew_world_request()
	_check(not fault_session.end_contact(func(e: Dictionary) -> WorldCommandResult: return fault_service.commit_batch(_batch([], e, 0, "KEEP_CURRENT"), e)), "new request cannot bypass activation fault")
	_check(fault_session.get_state_snapshot().phase == SessionPhase.Phase.CONTACT_PAUSED and fault_session.get_cycle_snapshot().simulation_tick == 0, "activation fault keeps simulation stopped")
	return true


func _coordinate_representability() -> bool:
	# Both signs wrap onto valid cells if int64 payloads narrow unchecked to Vector2i.
	for offset: int in [4294967296, -4294967296]:
		for command: Dictionary in [_move(3, [offset + 3, 2]), _map([offset + 4, 4]), _route([[1, 3], [offset + 2, 3]])]:
			var sync := RecordingSync.new()
			var service := WorldCommandService.new(_world(), _policy(), sync)
			var before: Dictionary = service.get_world_snapshot().to_snapshot()
			var commands: Array = [{"type": "AddDevice", "device": _plate([6, 6])}, command]
			var batch: WorldCommandBatch = _batch(commands, _context())
			var preview: WorldCommandResult = service.validate_batch(batch, _context())
			var label: String = command.type + " with coordinate offset " + str(offset)
			_check(preview != null and preview.status == "REJECTED", "preview rejects " + label)
			_check(service.get_world_snapshot().to_snapshot() == before and sync.prepares == 0 and sync.activates == 0, "invalid preview has no side effects: " + label)
			var receipt: WorldCommandResult = service.commit_batch(batch, _context())
			_check(receipt != null and receipt.status == "REJECTED" and receipt.created_ids.is_empty(), "commit rejects " + label)
			_check(service.get_world_snapshot().to_snapshot() == before and sync.prepares == 0 and sync.activates == 0, "overflow rejection preserves world, revision, IDs and sync: " + label)
		for axis: int in [0, 1]:
			var template_data: Dictionary = _fixture()
			template_data.grid_size[axis] += offset
			_check(LevelTemplate.from_data(template_data).instantiate_world() == null, "template dimension overflow rejected on axis " + str(axis) + " offset " + str(offset))
	var original: Dictionary = _world().to_snapshot()
	for field: String in ["player_position", "player_velocity", "origin"]:
		for oversized: float in [1e100, -1e100]:
			var invalid: Dictionary = original.duplicate(true)
			invalid[field] = [oversized, 1.0]
			_check(WorldState.from_snapshot(invalid) == null, "finite float64 cannot become non-finite Vector2: " + field + " " + str(oversized))
	var ordinary: Dictionary = original.duplicate(true)
	ordinary["origin"] = [0.25, -0.5]
	ordinary["player_position"] = [1.75, 1.0]
	ordinary["player_velocity"] = [1.25, -2.5]
	ordinary.entities[1].runtime_state.position = [1.75, 3.0]
	var decoded: WorldState = WorldState.from_snapshot(ordinary)
	_check(decoded != null, "representable vector values still decode")
	if decoded == null:
		return false
	_check(decoded.to_snapshot() == ordinary and decoded.snapshot_copy() != null, "representable vectors survive snapshot roundtrip")
	var scalar_bounds: Dictionary = _fixture()
	scalar_bounds.device_rules.parameter_ranges.camera.view_radius[1] = 1e100
	_check(LevelTemplate.from_data(scalar_bounds).instantiate_world() != null, "float64 scalar bounds are not restricted to Vector2 storage")
	var one_cell: Dictionary = _fixture()
	one_cell["grid_size"] = [1, 1]
	one_cell["terrain"] = [["FLOOR"]]
	one_cell["initial_entities"] = []
	one_cell["player_spawn"] = [0.0, 0.0]
	one_cell["cell_size"] = 1e100
	_check(LevelTemplate.from_data(one_cell).instantiate_world() == null, "finite scale that overflows calculated cell centers is rejected")
	one_cell["cell_size"] = 2.0
	_check(LevelTemplate.from_data(one_cell).instantiate_world() != null, "representable one-cell template remains valid")
	var robot_overflow: Dictionary = original.duplicate(true)
	robot_overflow.entities[1].runtime_state.position = [1e100, 3.5]
	_check(WorldState.from_snapshot(robot_overflow) == null, "robot runtime position must also fit finite Vector2 storage")
	var edge_cell: Array = [-2147483648, 2147483647]
	_check(DeviceRegistry.cell(edge_cell), "both int32 endpoints remain representable grid coordinates")
	var edge_service := WorldCommandService.new(_world(), _policy(), WorldSyncAdapter.new())
	var outside: WorldCommandResult = edge_service.commit_batch(_batch([_move(3, edge_cell)], _context()), _context())
	_check(outside != null and outside.status == "REJECTED" and edge_service.get_world_snapshot().to_snapshot() == original, "representable int32 endpoints are still outside this map")
	return true


func _plate_batch_final_position() -> bool:
	var initial: Dictionary = _world().to_snapshot()
	initial["player_position"] = [1.5, 3.5]
	initial.entities[2].cell = [1, 3]
	initial.entities[2].runtime_state = {"occupants": [0, 2], "baseline_ready": true}
	var sync := RecordingSync.new()
	var service := WorldCommandService.new(WorldState.from_snapshot(initial), _policy(), sync)
	var back_to_start: WorldCommandBatch = _batch([_move(3, [2, 3]), _move(3, [1, 3])], _context())
	var receipt: WorldCommandResult = service.commit_batch(back_to_start, _context())
	_check(receipt != null and receipt.status == "UNCHANGED", "atomic A-B-A pad moves are unchanged")
	_check(service.get_world_snapshot().to_snapshot() == initial, "A-B-A preserves the full world including occupied baseline and revision")
	_check(sync.prepares == 0 and sync.activates == 0, "A-B-A does not refresh derived state")
	# A genuinely different final position must still invalidate the entry baseline.
	var moved_sync := RecordingSync.new()
	var moved := WorldCommandService.new(WorldState.from_snapshot(initial), _policy(), moved_sync)
	var moved_receipt: WorldCommandResult = moved.commit_batch(_batch([_move(3, [2, 3])], _context()), _context())
	_check(moved_receipt != null and moved_receipt.status == "APPLIED", "actual A-B movement applies")
	var moved_world: WorldState = moved.get_world_snapshot()
	_check(moved_world.registry.get_entity(3).cell == [2, 3] and moved_world.registry.get_entity(3).runtime_state == {"occupants": [], "baseline_ready": false}, "actual movement invalidates occupied baseline")
	_check(moved_world.world_revision == initial.world_revision + 1 and moved_sync.prepares == 1 and moved_sync.activates == 1, "actual movement increments revision and synchronizes once")
	for removal_index: int in [0, 1, 2]:
		var commands: Array = [_move(3, [2, 3]), _move(3, [1, 3])]
		commands.insert(removal_index, {"type": "RemoveDevice", "id": 2})
		var remove_sync := RecordingSync.new()
		var removing := WorldCommandService.new(WorldState.from_snapshot(initial), _policy(), remove_sync)
		var removal: WorldCommandResult = removing.commit_batch(_batch(commands, _context()), _context())
		_check(removal != null and removal.status == "APPLIED", "remove robot plus A-B-A applies at command index " + str(removal_index))
		var final_world: WorldState = removing.get_world_snapshot()
		_check(final_world.registry.get_entity(2).is_empty() and final_world.registry.get_entity(3).runtime_state == {"occupants": [0], "baseline_ready": true}, "baseline keeps surviving occupant without reviving removed robot")
		_check(final_world.next_entity_id == initial.next_entity_id and final_world.world_revision == initial.world_revision + 1 and remove_sync.activates == 1, "combined removal preserves allocator and synchronizes once")
	return true
