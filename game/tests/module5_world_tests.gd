extends RefCounted
class_name Module5WorldTests
## Module 5 migration contracts. All numbers are graybox fixtures.

var passed: int = 0
var failed: int = 0


func run() -> Dictionary:
	_check(_independent_camera(), "camera installs without a mount wall")
	_check(_obstacle_snapshot(), "stable obstacle instance survives a world snapshot")
	_check(await _obstacle_scene(), "fixed house scene covers the stable footprint")
	_check(_obstacle_dispatch(), "moving a house commits all four cells through scene sync")
	_check(_protected_obstacle_rejected(), "protected placement has only a safe rejection")
	_check(_public_world_whitelist(), "system view contains current world without private state")
	_check(await _blocked_robot(), "house cuts future patrol without faulting robot motion")
	_check(_public_history_whitelist(), "current public view rejects private history injection")
	_check(_camera_limits_and_scan(), "camera coexistence, scan phase and final device cap")
	_check(_robot_placement_and_path(), "new robot checks real overlap and anchored route")
	_check(_obstacle_vision(), "whole house occludes supercover rays")
	_check(_real_device_dispatch(), "camera robot plate and house commit through real scene sync")
	return {"passed": passed, "failed": failed}


func _check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		push_error("MODULE 5 WORLD TEST FAILED: " + label)


func _rules() -> Dictionary:
	return {"parameter_ranges": {
		"camera": {"view_radius": [1.0, 1000.0], "fov_angle": [0.1, TAU], "scan_center": [-PI, PI], "scan_half_angle": [0.0, PI], "scan_speed": [0.0, 4.0]},
		"robot": {"view_radius": [1.0, 1000.0], "move_speed": [0.1, 400.0]},
	}, "camera_per_anchor": 1}


func _level() -> Dictionary:
	var terrain: Array = []
	for y: int in 6:
		var row: Array = []
		for x: int in 6:
			row.append("WALL" if x == 0 or y == 0 or x == 5 or y == 5 else "FLOOR")
		terrain.append(row)
	return {"template_key": "module5_world_fixture", "grid_size": [6, 6], "cell_size": 64.0,
		"origin": [0.0, 0.0], "terrain": terrain, "player_spawn": [96.0, 96.0],
		"device_rules": _rules(), "initial_entities": [{"kind": "camera", "cell": [2, 2],
			"parameters": {"enabled": true, "view_radius": 128.0, "fov_angle": 1.0,
				"scan_center": 0.0, "scan_half_angle": 0.5, "scan_speed": 1.0}}],
		"obstacle_templates": [{"template_id": "house", "footprint": [[0, 0], [1, 0], [0, 1], [1, 1]],
			"blocks_movement": true, "blocks_vision": true, "scene_path": "res://scenes/runtime/obstacle_view.tscn"}],
		"initial_obstacles": [{"template_id": "house", "anchor_cell": [3, 2]}]}


func _independent_camera() -> bool:
	var data: Dictionary = _level()
	data.initial_obstacles = []
	var world: WorldState = LevelTemplate.from_data(data).instantiate_world()
	if world == null or world.registry.to_snapshot().size() != 1 or world.registry.get_entity(1).has("mount_type"):
		return false
	var legacy: Dictionary = data.duplicate(true)
	legacy.initial_entities[0]["mount_type"] = "wall"
	if LevelTemplate.from_data(legacy).instantiate_world() != null:
		return false
	data.initial_entities.append({"kind": "robot", "cell": [2, 2], "parameters": {"view_radius": 128.0, "move_speed": 60.0}, "patrol_path": [[2, 2]]})
	var shared: WorldState = LevelTemplate.from_data(data).instantiate_world()
	return shared != null and not shared.get_cell_profile(Vector2i(2, 2)).blocks_movement


func _obstacle_snapshot() -> bool:
	var world: WorldState = LevelTemplate.from_data(_level()).instantiate_world()
	if world == null:
		return false
	var snapshot: Dictionary = world.to_snapshot()
	var restored: WorldState = WorldState.from_snapshot(snapshot)
	var old_schema: Dictionary = snapshot.duplicate(true)
	old_schema.schema_version = 1
	var rotated: Dictionary = snapshot.duplicate(true)
	rotated.obstacle_instances[0]["orientation"] = 90
	return restored != null and snapshot.get("schema_version") == 2 \
		and WorldState.from_snapshot(old_schema) == null and WorldState.from_snapshot(rotated) == null \
		and snapshot.get("obstacle_instances", []).size() == 1 \
		and restored.get_cell_profile(Vector2i(3, 2)).blocks_movement \
		and restored.get_cell_profile(Vector2i(4, 3)).blocks_vision


func _obstacle_scene() -> bool:
	var world: WorldState = LevelTemplate.from_data(_level()).instantiate_world()
	if world == null:
		return false
	var view := RuntimeWorldView.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(view)
	var built: bool = view.build_from_world(world)
	var house: Node = view.find_child("Obstacle1", true, false)
	var ok: bool = built and house is Node2D and house.get_node_or_null("Sprite2D") is Sprite2D \
		and house.get_node_or_null("StaticBody2D/CollisionShape2D") is CollisionShape2D \
		and (house as Node2D).position.is_equal_approx(world.origin + Vector2(3, 2) * world.cell_size)
	if ok:
		await (Engine.get_main_loop() as SceneTree).physics_frame
		var body: StaticBody2D = house.get_node("StaticBody2D") as StaticBody2D
		for cell: Vector2i in world.obstacle_cells(1):
			var query := PhysicsPointQueryParameters2D.new()
			query.position = world.cell_to_world(cell)
			query.collision_mask = 1
			var hits: Array[Dictionary] = view.get_world_2d().direct_space_state.intersect_point(query)
			if not hits.any(func(hit: Dictionary) -> bool: return hit.get("collider") == body):
				ok = false
	view.queue_free()
	return ok


func _context(request_id: int) -> Dictionary:
	var result: Dictionary = AgentProtocol.make_request_context(AgentProtocol.SYSTEM_AGENT, request_id, 1, 1, 1)
	result["phase"] = SessionPhase.Phase.DISPATCH_PAUSED
	return result


func _batch(command: Dictionary, context: Dictionary, revision: int = 0) -> WorldCommandBatch:
	return WorldCommandBatch.from_data({"context": AgentProtocol.serialize_context(context), "source": "dispatch",
		"base_world_revision": revision, "mode": "APPLY", "commands": [command]})


func _policy() -> Dictionary:
	var cells: Array = []
	for y: int in range(1, 5):
		for x: int in range(1, 5):
			cells.append([x, y])
	return {AgentProtocol.SYSTEM_AGENT: {"commands": {"MoveObstacle": ["obstacle"], "AddDevice": ["camera", "robot", "pressure_plate"],
		"RemoveDevice": ["camera", "robot", "pressure_plate"], "MoveDevice": ["camera", "pressure_plate"],
		"SetCameraScanState": ["camera"], "SetDeviceParameter": ["camera"], "SetPatrolPath": ["robot"]},
		"parameters": {"camera": ["scan_center", "scan_half_angle"]},
		"max_commands": 1, "allowed_cells": cells, "device_limits": {"camera": 2, "robot": 2, "pressure_plate": 1},
		"obstacle_protection_radius": 0}}


func _obstacle_dispatch() -> bool:
	var world: WorldState = LevelTemplate.from_data(_level()).instantiate_world()
	var view := RuntimeWorldView.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(view)
	if world == null or not view.build_from_world(world):
		view.queue_free()
		return false
	var service := WorldCommandService.new(world, _policy(), SceneWorldSyncAdapter.new(view))
	var initial_texture: Texture2D = (view.find_child("Obstacle1", true, false).get_node("Sprite2D") as Sprite2D).texture
	var context: Dictionary = _context(31)
	var result: WorldCommandResult = service.commit_batch(_batch({"type": "MoveObstacle", "obstacle_id": 1, "anchor_cell": [2, 3]}, context), context)
	var moved: WorldState = service.get_world_snapshot()
	var house: Node2D = view.find_child("Obstacle1", true, false) as Node2D
	var ok: bool = result.status == "APPLIED" and moved.world_revision == 1 \
		and moved.obstacle_instances[0].anchor_cell == [2, 3] and house != null \
		and house.position.is_equal_approx(Vector2(128, 192)) \
		and (house.get_node("Sprite2D") as Sprite2D).texture == initial_texture \
		and moved.get_cell_profile(Vector2i(3, 4)).blocks_vision \
		and not moved.get_cell_profile(Vector2i(4, 2)).blocks_vision
	var invalid_context: Dictionary = _context(33)
	var unchanged: Dictionary = moved.to_snapshot()
	var invalid: WorldCommandResult = service.commit_batch(_batch({"type": "MoveObstacle", "obstacle_id": 1, "anchor_cell": [4, 3]}, invalid_context, 1), invalid_context)
	ok = ok and invalid.status == "REJECTED" and service.get_world_snapshot().to_snapshot() == unchanged \
		and (view.find_child("Obstacle1", true, false) as Node2D).position.is_equal_approx(Vector2(128, 192))
	view.queue_free()
	return ok


func _protected_obstacle_rejected() -> bool:
	var data: Dictionary = _level()
	data.initial_entities = []
	var world: WorldState = LevelTemplate.from_data(data).instantiate_world()
	if world == null:
		return false
	var policy: Dictionary = _policy()
	policy[AgentProtocol.SYSTEM_AGENT]["obstacle_protection_radius"] = 1
	var view := RuntimeWorldView.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(view)
	if not view.build_from_world(world):
		view.queue_free()
		return false
	var service := WorldCommandService.new(world, policy, SceneWorldSyncAdapter.new(view))
	var context: Dictionary = _context(32)
	var before: Dictionary = service.get_world_snapshot().to_snapshot()
	var preview: WorldCommandResult = service.validate_batch(_batch({"type": "MoveObstacle", "obstacle_id": 1, "anchor_cell": [1, 2]}, context), context)
	var result: WorldCommandResult = service.commit_batch(_batch({"type": "MoveObstacle", "obstacle_id": 1, "anchor_cell": [1, 2]}, context), context)
	var safe: Dictionary = result.safe_dispatch_receipt() if result.has_method("safe_dispatch_receipt") else {}
	var ok: bool = preview.status == "VALID" and result.status == "REJECTED" and not result.errors.is_empty() \
		and result.errors[0].code == "PLACEMENT_REJECTED" and service.get_world_snapshot().to_snapshot() == before \
		and safe.get("status") == "REJECTED" and not str(safe).contains("player")
	view.queue_free()
	return ok


func _public_world_whitelist() -> bool:
	var world: WorldState = LevelTemplate.from_data(_level()).instantiate_world()
	if world == null:
		return false
	var view := SystemAgentView.new()
	if not view.initialize(world):
		return false
	var data: Dictionary = view.to_data()
	if not data.has("world") or not data.world is Dictionary:
		return false
	var public: Dictionary = data.world
	return DeviceRegistry.fields(data, ["world", "reports", "history"]) \
		and DeviceRegistry.fields(public, ["grid_size", "cell_size", "origin", "terrain", "obstacle_templates",
			"obstacle_instances", "cameras", "robots", "fixed_entities", "world_revision", "device_counts", "dispatch_rules"]) \
		and public.obstacle_instances.size() == 1 and not public.obstacle_templates[0].has("scene_path") \
		and not str(data).contains("player_position") and not str(data).contains("next_entity_id")


func _blocked_robot() -> bool:
	var data: Dictionary = PrototypeConfig.level_data()
	data.initial_obstacles[0].anchor_cell = [6, 2]
	var world: WorldState = LevelTemplate.from_data(data).instantiate_world()
	if world == null:
		return false
	var view := RuntimeWorldView.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(view)
	if not view.build_from_world(world):
		view.queue_free()
		return false
	var robot: RobotController = view.get_entity_node(2) as RobotController
	var entity: Dictionary = world.registry.get_entity(2)
	var valid: bool = robot != null
	for _i: int in 160:
		await (Engine.get_main_loop() as SceneTree).physics_frame
		if not valid:
			break
		var next: Dictionary = robot.advance(entity, world, view.get_player(), 1.0 / 60.0)
		if next.is_empty():
			valid = false
			break
		entity.runtime_state = next
	valid = valid and robot.global_position.x < world.cell_to_world(Vector2i(6, 3)).x - 10.0
	view.queue_free()
	return valid


func _public_history_whitelist() -> bool:
	var world: WorldState = LevelTemplate.from_data(PrototypeConfig.level_data()).instantiate_world()
	var view := SystemAgentView.new()
	if world == null or not view.initialize(world, PrototypeConfig.system_dispatch_policy()):
		return false
	var bad: Dictionary = view.snapshot()
	bad.history.append({"kind": "guess", "player_cell": [1, 1]})
	if view.restore(bad):
		return false
	var public: Dictionary = view.snapshot().world
	return public.robots.size() == 1 and public.world_revision == 0 and public.device_counts == {"camera": 1, "robot": 1, "pressure_plate": 1} \
		and public.dispatch_rules.device_limits.camera == 2 and DeviceRegistry.fields(public.robots[0],
		["id", "position", "cell", "path_index", "progress", "travel_direction", "transition", "patrol_path", "parameters"]) \
		and public.robots[0].cell == [4, 3]


func _camera_limits_and_scan() -> bool:
	var world: WorldState = LevelTemplate.from_data(_level()).instantiate_world()
	if world == null:
		return false
	var policy: Dictionary = _policy()
	policy[AgentProtocol.SYSTEM_AGENT]["obstacle_protection_radius"] = 1
	var service := WorldCommandService.new(world, policy, WorldSyncAdapter.new())
	var scan_context: Dictionary = _context(41)
	var scan: WorldCommandResult = service.commit_batch(_batch({"type": "SetCameraScanState", "id": 1,
		"heading": 0.2, "scan_direction": -1}, scan_context), scan_context)
	if scan.status != "APPLIED" or service.get_world_snapshot().registry.get_entity(1).runtime_state.scan_direction != -1:
		return false
	var data: Dictionary = _level().initial_entities[0]
	data.cell = [1, 2]
	var add_context: Dictionary = _context(42)
	var added: WorldCommandResult = service.commit_batch(_batch({"type": "AddDevice", "device": data}, add_context, 1), add_context)
	if added.status != "APPLIED" or service.get_world_snapshot().world_revision != 2:
		return false
	data.cell = [1, 3]
	var cap_context: Dictionary = _context(43)
	var capped: WorldCommandResult = service.commit_batch(_batch({"type": "AddDevice", "device": data}, cap_context, 2), cap_context)
	if capped.status != "REJECTED" or capped.errors[0].code != "DEVICE_LIMIT" or service.get_world_snapshot().world_revision != 2:
		return false
	var plate_context: Dictionary = _context(44)
	var plate: WorldCommandResult = service.commit_batch(_batch({"type": "AddDevice", "device": {"kind": "pressure_plate", "cell": [2, 2], "parameters": {}}}, plate_context, 2), plate_context)
	if plate.status != "APPLIED" or service.get_world_snapshot().registry.get_entity(3).cell != [2, 2]:
		return false
	var map_context: Dictionary = _context(45)
	var map_edit: WorldCommandResult = service.commit_batch(_batch({"type": "SetMapCell", "cell": [1, 3], "cell_kind": "WALL"}, map_context, 3), map_context)
	return map_edit.status == "REJECTED" and map_edit.errors[0].code == "PERMISSION_DENIED"


func _robot_placement_and_path() -> bool:
	var world: WorldState = LevelTemplate.from_data(_level()).instantiate_world()
	if world == null:
		return false
	var policy: Dictionary = _policy()
	policy[AgentProtocol.SYSTEM_AGENT]["obstacle_protection_radius"] = 2
	var service := WorldCommandService.new(world, policy, WorldSyncAdapter.new())
	var robot: Dictionary = {"kind": "robot", "cell": [1, 3], "parameters": {"view_radius": 128.0, "move_speed": 60.0},
		"patrol_path": [[1, 3], [2, 3]]}
	var context: Dictionary = _context(51)
	var added: WorldCommandResult = service.commit_batch(_batch({"type": "AddDevice", "device": robot}, context), context)
	if added.status != "APPLIED":
		return false
	context = _context(52)
	var overlap: WorldCommandResult = service.commit_batch(_batch({"type": "AddDevice", "device": robot}, context, 1), context)
	if overlap.status != "REJECTED" or overlap.errors[0].code != "PLACEMENT_REJECTED":
		return false
	context = _context(53)
	var bad_path: WorldCommandResult = service.commit_batch(_batch({"type": "SetPatrolPath", "robot_id": 2,
		"cells": [[2, 3], [1, 3]]}, context, 1), context)
	if bad_path.status != "REJECTED" or bad_path.errors[0].code != "INVALID_PATH":
		return false
	robot.cell = [1, 1]
	robot.patrol_path = [[1, 1]]
	context = _context(54)
	var player_overlap: WorldCommandResult = service.commit_batch(_batch({"type": "AddDevice", "device": robot}, context, 1), context)
	return player_overlap.status == "REJECTED" and player_overlap.errors[0].code == "PLACEMENT_REJECTED" \
		and service.get_world_snapshot().world_revision == 1


func _obstacle_vision() -> bool:
	var blocked: WorldState = LevelTemplate.from_data(_level()).instantiate_world()
	var open_data: Dictionary = _level()
	open_data.initial_obstacles = []
	var clear: WorldState = LevelTemplate.from_data(open_data).instantiate_world()
	if blocked == null or clear == null:
		return false
	var from: Vector2 = blocked.cell_to_world(Vector2i(2, 2))
	return not VisionGeometry.is_cell_reliable(blocked, from, Vector2i(4, 4)) \
		and VisionGeometry.is_cell_reliable(clear, from, Vector2i(4, 4))


func _real_device_dispatch() -> bool:
	var world: WorldState = LevelTemplate.from_data(PrototypeConfig.level_data()).instantiate_world()
	if world == null:
		return false
	var view := RuntimeWorldView.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(view)
	if not view.build_from_world(world):
		view.queue_free()
		return false
	var service := WorldCommandService.new(world, PrototypeConfig.combined_policy(), SceneWorldSyncAdapter.new(view))
	var commands: Array[Dictionary] = [
		{"type": "AddDevice", "device": {"kind": "camera", "cell": [2, 2], "parameters": {"enabled": true,
			"view_radius": 320.0, "fov_angle": 1.2, "scan_center": 0.0, "scan_half_angle": 0.8, "scan_speed": 1.0}}},
		{"type": "AddDevice", "device": {"kind": "robot", "cell": [8, 5],
			"parameters": {"view_radius": 320.0, "move_speed": 60.0}, "patrol_path": [[8, 5], [8, 6]]}},
		{"type": "AddDevice", "device": {"kind": "pressure_plate", "cell": [2, 2], "parameters": {}}},
		{"type": "MoveObstacle", "obstacle_id": 1, "anchor_cell": [8, 2]},
	]
	var all_applied: bool = true
	for index: int in commands.size():
		var context: Dictionary = _context(70 + index)
		var result: WorldCommandResult = service.commit_batch(_batch(commands[index], context, index), context)
		all_applied = all_applied and result.status == "APPLIED" and result.revision_after == index + 1
		if not all_applied:
			break
	var committed: WorldState = service.get_world_snapshot()
	var ok: bool = all_applied and committed.world_revision == 4 and view.get_entity_node(7) is DeviceView \
		and view.get_entity_node(8) is RobotController and view.get_entity_node(9) is DeviceView \
		and view.find_child("Obstacle1", true, false) is ObstacleView \
		and committed.obstacle_instances[0].anchor_cell == [8, 2]
	view.queue_free()
	return ok
