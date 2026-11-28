extends RefCounted
class_name RuntimeSceneTests


class FailingSceneAdapter extends SceneWorldSyncAdapter:
	func activate(prepared: Dictionary) -> bool:
		if prepared.get("terrain") != null:
			prepared.terrain.queue_free()
		for node: Node in prepared.get("changed", {}).values():
			node.queue_free()
		return false


class TrackingWorldView extends RuntimeWorldView:
	var created_nodes: Array[Node] = []

	func make_terrain_layer(world_data: Dictionary) -> TileMapLayer:
		var layer: TileMapLayer = super.make_terrain_layer(world_data)
		if layer != null:
			created_nodes.append(layer)
		return layer

	func make_entity_node(entity: Dictionary) -> Node2D:
		var node: Node2D = super.make_entity_node(entity)
		if node != null:
			created_nodes.append(node)
		return node


class ForcedInteractionView extends RuntimeWorldView:
	var forced_interaction: Dictionary = {}

	func step_motion(candidate: WorldState, input_vector: Vector2, delta: float, rules: Dictionary, expected_tick: int = 0, interact_pressed: bool = false, cancel_pressed: bool = false) -> Array[Dictionary]:
		var errors: Array[Dictionary] = super.step_motion(candidate, input_vector, delta, rules, expected_tick, interact_pressed, cancel_pressed)
		last_interaction = forced_interaction.duplicate(true)
		return errors


const SOLID: int = 1
const PLAYER: int = 2
const ROBOT: int = 4

var passed: int = 0
var failed: int = 0


func run() -> Dictionary:
	for scenario: Callable in [_player_acceleration, _player_collision, _player_diagonal, _robot_open_push, _robot_pinch_pause, _fixed_facility_collision, _deployment_sync, _activation_fault_lock, _runtime_cycle, _runtime_fault_lock, _runtime_push_world_consistency, _runtime_stays_action, _prepare_failure_discards_nodes, _player_cannot_push_robot, _robot_real_patrol, _all_phases_freeze, _interaction_fixture, _goal_operation, _goal_completion_all, _contact_flow, _contact_boundary_priority, _exit_completion, _contact_successful_retry, _goal_input_validation, _goal_robot_push_cancel, _domain_event_boundary, _exit_guess_priority, _goal_residual_velocity_cancel, _contact_input_keep_current, _contact_success_priority]:
		_check(await scenario.call() == true, "scenario completed: " + scenario.get_method())
	return {"passed": passed, "failed": failed}


func _check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		push_error("RUNTIME SCENE TEST FAILED: " + label)


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _rules() -> Dictionary:
	return {"max_speed": 120.0, "acceleration": 600.0, "deceleration": 800.0}


func _make_world() -> Node2D:
	var world := Node2D.new()
	_tree().root.add_child(world)
	return world


func _make_player(world: Node2D, position: Vector2) -> PlayerController:
	var player: PlayerController = load("res://scenes/runtime/player.tscn").instantiate()
	world.add_child(player)
	player.global_position = position
	return player


func _make_wall(world: Node2D, position: Vector2, size: Vector2) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.collision_layer = SOLID
	body.collision_mask = PLAYER | ROBOT
	body.global_position = position
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = size
	shape.shape = rectangle
	body.add_child(shape)
	world.add_child(body)
	return body


func _settle() -> void:
	for _i: int in 3:
		await _tree().physics_frame


func _free_world(world: Node2D) -> void:
	world.queue_free()
	await _tree().process_frame


func _player_acceleration() -> bool:
	var world := _make_world()
	var player := _make_player(world, Vector2(100, 100))
	await _settle()
	for _i: int in 60:
		await _tree().physics_frame
		player.advance(Vector2.RIGHT, 1.0 / 60.0, _rules())
	_check(player.velocity.is_equal_approx(Vector2(120, 0)), "player reaches configured max speed")
	_check(player.global_position.x > 180.0, "player advances using real physics")
	var moving_position: Vector2 = player.global_position
	for _i: int in 30:
		await _tree().physics_frame
		player.advance(Vector2.ZERO, 1.0 / 60.0, _rules())
	_check(player.velocity.is_zero_approx(), "player decelerates to rest")
	_check(player.global_position.distance_to(moving_position) < 30.0, "deceleration has bounded stopping distance")
	var state: Dictionary = player.motion_state()
	_check(DeviceRegistry.vector_point(state.position) and DeviceRegistry.vector_point(state.velocity), "player motion state is finite plain data")
	await _free_world(world)
	return true


func _player_collision() -> bool:
	var world := _make_world()
	var player := _make_player(world, Vector2(180, 100))
	var wall := _make_wall(world, Vector2(260, 100), Vector2(20, 100))
	await _settle()
	for _i: int in 90:
		await _tree().physics_frame
		player.advance(Vector2.RIGHT, 1.0 / 60.0, _rules())
	_check(player.global_position.x <= wall.global_position.x - 19.0, "player cannot cross solid wall")
	_check(player.global_position.x > 220.0, "player still approaches wall before collision")
	await _free_world(world)
	return true


func _player_diagonal() -> bool:
	var world := _make_world()
	var player := _make_player(world, Vector2(100, 100))
	await _settle()
	for _i: int in 60:
		await _tree().physics_frame
		player.advance(Vector2.ONE, 1.0 / 60.0, _rules())
	_check(player.velocity.length() <= 120.01, "diagonal input does not exceed max speed")
	_check(player.velocity.x > 0.0 and player.velocity.y > 0.0, "diagonal input preserves both axes")
	await _free_world(world)
	return true


func _device_rules() -> Dictionary:
	return {
		"parameter_ranges": {
			"camera": {"view_radius": [0.1, 2000.0], "fov_angle": [0.1, TAU], "scan_center": [-PI, PI], "scan_half_angle": [0.0, PI], "scan_speed": [0.0, 400.0]},
			"robot": {"view_radius": [0.1, 2000.0], "move_speed": [0.1, 400.0]},
		},
		"camera_mount_limits": {"wall": {"half_angle": PI / 2.0}, "ceiling": {"center": 0.0, "half_angle": PI}},
		"camera_per_anchor": 1,
	}


func _patrol_world(path: Array) -> WorldState:
	var terrain: Array = []
	for y: int in 5:
		var row: Array = []
		for x: int in 5:
			row.append("WALL" if x == 0 or y == 0 or x == 4 or y == 4 else "FLOOR")
		terrain.append(row)
	return LevelTemplate.from_data({
		"template_key": "robot_scene_test", "grid_size": [5, 5], "cell_size": 100.0, "origin": [0.0, 0.0],
		"terrain": terrain, "player_spawn": [150.0, 350.0], "device_rules": _device_rules(),
		"initial_entities": [{"kind": "robot", "cell": path[0], "parameters": {"view_radius": 400.0, "move_speed": 100.0}, "patrol_path": path}],
	}).instantiate_world()


func _make_robot(world: Node2D, entity_id: int, position: Vector2) -> RobotController:
	var robot: RobotController = load("res://scenes/runtime/robot.tscn").instantiate()
	world.add_child(robot)
	robot.configure(entity_id)
	robot.global_position = position
	return robot


func _robot_open_push() -> bool:
	var data := _patrol_world([[1, 1], [2, 1]])
	var entity: Dictionary = data.registry.get_entity(1)
	var world := _make_world()
	var player := _make_player(world, Vector2(200, 150))
	var player_start: Vector2 = player.global_position
	var robot := _make_robot(world, 1, Vector2(150, 150))
	await _settle()
	for _i: int in 40:
		await _tree().physics_frame
		var next: Dictionary = robot.advance(entity, data, player, 1.0 / 60.0)
		_check(not next.is_empty(), "open patrol step accepted")
		if not next.is_empty():
			entity.runtime_state = next
		player.velocity = Vector2.ZERO
		player.move_and_slide()
	_check(robot.global_position.x > 210.0, "robot keeps moving in open area")
	_check(player.global_position.x > player_start.x + 5.0, "robot pushes player in open area")
	_check(player.global_position.x > robot.global_position.x, "player remains ahead of moving robot")
	await _free_world(world)
	return true


func _robot_pinch_pause() -> bool:
	var data := _patrol_world([[1, 2], [2, 2]])
	var entity: Dictionary = data.registry.get_entity(1)
	entity.runtime_state.position = [180.0, 250.0]
	entity.runtime_state.progress = 0.3
	var world := _make_world()
	var player := _make_player(world, Vector2(220, 250))
	var robot := _make_robot(world, 1, Vector2(180, 250))
	var wall := _make_wall(world, Vector2(260, 250), Vector2(20, 100))
	await _settle()
	for _i: int in 90:
		await _tree().physics_frame
		var next: Dictionary = robot.advance(entity, data, player, 1.0 / 60.0)
		if not next.is_empty():
			entity.runtime_state = next
		player.velocity = Vector2.ZERO
		player.move_and_slide()
	var stopped: Vector2 = robot.global_position
	_check(robot.global_position.x < player.global_position.x, "pinched robot does not cross player")
	_check(player.global_position.x <= wall.global_position.x - 19.0, "pinched player does not cross wall")
	for _i: int in 20:
		await _tree().physics_frame
		player.velocity = Vector2(0, -120)
		player.move_and_slide()
		var next: Dictionary = robot.advance(entity, data, player, 1.0 / 60.0)
		if not next.is_empty():
			entity.runtime_state = next
	_check(robot.global_position.x > stopped.x + 5.0, "robot resumes after player leaves pinch")
	await _free_world(world)
	return true


func _view_world() -> WorldState:
	var terrain: Array = []
	for y: int in 6:
		var row: Array = []
		for x: int in 6:
			row.append("WALL" if x == 0 or y == 0 or x == 5 or y == 5 else "FLOOR")
		terrain.append(row)
	return LevelTemplate.from_data({
		"template_key": "scene_sync_test", "grid_size": [6, 6], "cell_size": 64.0, "origin": [0.0, 0.0],
		"terrain": terrain, "player_spawn": [96.0, 288.0], "device_rules": _device_rules(),
		"initial_entities": [
			{"kind": "camera", "cell": [2, 2], "mount_type": "ceiling", "parameters": {"enabled": true, "view_radius": 384.0, "fov_angle": 1.0, "scan_center": 0.0, "scan_half_angle": 0.5, "scan_speed": 1.0}},
			{"kind": "robot", "cell": [1, 3], "parameters": {"view_radius": 384.0, "move_speed": 64.0}, "patrol_path": [[1, 3], [2, 3]]},
			{"kind": "pressure_plate", "cell": [2, 2], "parameters": {}},
			{"kind": "goal", "cell": [4, 4], "parameters": {}},
			{"kind": "contact", "cell": [4, 1], "parameters": {}},
			{"kind": "exit", "cell": [4, 3], "parameters": {}},
		],
	}).instantiate_world()


func _make_view(data: WorldState) -> RuntimeWorldView:
	var view: RuntimeWorldView = load("res://scenes/runtime/runtime_test.tscn").instantiate()
	_tree().root.add_child(view)
	view.build_from_world(data)
	return view


func _command_policy() -> Dictionary:
	var system_rules: Dictionary = {"commands": {
		"SetMapCell": ["map"], "AddDevice": ["pressure_plate"], "RemoveDevice": ["pressure_plate"],
		"MoveDevice": ["camera"], "SetDeviceParameter": ["camera"], "SetPatrolPath": ["robot"],
	}, "parameters": {"camera": DeviceRegistry.CAMERA_NUMBERS.duplicate() + ["enabled"]}}
	var assistant_rules: Dictionary = {"commands": {"SetDeviceParameter": ["camera"]}, "parameters": {"camera": ["scan_center", "scan_half_angle"]}}
	return {AgentProtocol.SYSTEM_AGENT: system_rules, AgentProtocol.PLAYER_ASSISTANT: assistant_rules}


func _dispatch_context(request_id: int = 1) -> Dictionary:
	var context: Dictionary = AgentProtocol.make_request_context(AgentProtocol.SYSTEM_AGENT, request_id, 1, 1, 1)
	context["phase"] = SessionPhase.Phase.DISPATCH_PAUSED
	return context


func _commit(service: WorldCommandService, commands: Array, revision: int) -> WorldCommandResult:
	var context: Dictionary = _dispatch_context(revision + 1)
	var batch := WorldCommandBatch.from_data({"context": AgentProtocol.serialize_context(context), "source": "dispatch", "base_world_revision": revision, "mode": "APPLY", "commands": commands})
	return service.commit_batch(batch, context)


func _fixed_facility_collision() -> bool:
	var data := _view_world()
	var view := _make_view(data)
	var player := view.get_player()
	player.global_position = Vector2(160, 288)
	await _settle()
	for _i: int in 90:
		await _tree().physics_frame
		player.advance(Vector2.RIGHT, 1.0 / 60.0, _rules())
	_check(player.global_position.x <= 247.0, "fixed goal blocks real player movement")
	_check(player.global_position.x > 220.0, "player approaches fixed goal before collision")
	var goal_view: DeviceView = view.get_entity_node(4)
	_check(goal_view.body.polygon.size() == 4 and goal_view.body.polygon[0] != Vector2.ZERO, "fixed facility has non-empty graybox polygon")
	_check(view._terrain.get_cell_atlas_coords(Vector2i(0, 0)) == Vector2i(1, 0), "wall cell uses collidable wall tile")
	_check(view._terrain.get_cell_atlas_coords(Vector2i(1, 1)) == Vector2i(0, 0), "floor cell uses non-solid floor tile")
	view.queue_free()
	await _tree().process_frame
	return true


func _deployment_sync() -> bool:
	var data := _view_world()
	var camera: Dictionary = data.registry.get_entity(1)
	camera.runtime_state.heading = 0.25
	data.registry._put(camera)
	var view := _make_view(data)
	var adapter := SceneWorldSyncAdapter.new(view)
	var service := WorldCommandService.new(data, _command_policy(), adapter)
	await _settle()
	var original_camera: Node2D = view.get_entity_node(1)
	var added: WorldCommandResult = _commit(service, [{"type": "AddDevice", "device": {"kind": "pressure_plate", "cell": [3, 3], "parameters": {}}}], 0)
	_check(added.status == "APPLIED" and added.created_ids.size() == 1, "real scene accepts new plate")
	var new_id: int = added.created_ids[0].id
	_check(view.get_entity_node(new_id) != null, "new plate has scene node with stable ID")
	_check(view.get_entity_node(1) == original_camera, "unrelated camera node is not rebuilt")

	var moved: WorldCommandResult = _commit(service, [{"type": "MoveDevice", "id": 1, "cell": [1, 2], "mount_type": "ceiling"}], 1)
	_check(moved.status == "APPLIED", "camera move activates")
	var moved_camera: DeviceView = view.get_entity_node(1)
	_check(moved_camera.position.is_equal_approx(Vector2(96, 160)), "moved camera uses world coordinate conversion")
	_check(is_equal_approx(moved_camera.rotation, 0.25), "camera scan phase survives deployment")

	var terrain_result: WorldCommandResult = _commit(service, [{"type": "SetMapCell", "cell": [3, 2], "cell_kind": "WALL"}], 2)
	_check(terrain_result.status == "APPLIED", "terrain change activates")
	_check(view._terrain.get_cell_atlas_coords(Vector2i(3, 2)) == Vector2i(1, 0), "terrain view matches committed wall")
	var player := view.get_player()
	player.global_position = Vector2(160, 160)
	for _i: int in 60:
		await _tree().physics_frame
		player.advance(Vector2.RIGHT, 1.0 / 60.0, _rules())
	_check(player.global_position.x <= 183.0, "new wall blocks real player collision")
	var floor_result: WorldCommandResult = _commit(service, [{"type": "SetMapCell", "cell": [3, 2], "cell_kind": "FLOOR"}], 3)
	_check(floor_result.status == "APPLIED", "terrain restoration activates")
	for _i: int in 30:
		await _tree().physics_frame
		player.advance(Vector2.RIGHT, 1.0 / 60.0, _rules())
	_check(player.global_position.x > 192.0, "restored floor allows real player movement")

	var removed: WorldCommandResult = _commit(service, [{"type": "RemoveDevice", "id": new_id}], 4)
	_check(removed.status == "APPLIED", "plate removal activates")
	_check(view.get_entity_node(new_id) == null, "removed plate node leaves active scene")

	var old_terrain: TileMapLayer = view._terrain
	var rejected: Dictionary = adapter.prepare(data.to_snapshot(), {}, {"terrain_changed": true, "changed_ids": [], "removed_ids": []})
	_check(rejected.get("ok") == false, "invalid prepared terrain is rejected")
	_check(view._terrain == old_terrain, "prepare rejection preserves active terrain")
	view.queue_free()
	await _tree().process_frame
	return true


func _activation_fault_lock() -> bool:
	var data := _view_world()
	var view := _make_view(data)
	var service := WorldCommandService.new(data, _command_policy(), FailingSceneAdapter.new(view))
	var result: WorldCommandResult = _commit(service, [{"type": "AddDevice", "device": {"kind": "pressure_plate", "cell": [3, 3], "parameters": {}}}], 0)
	_check(result.status == "REJECTED" and result.errors[0].code == "SYNC_ACTIVATION_FAILED", "activation fault is not reported as success")
	_check(service.get_world_snapshot().world_revision == 0, "activation fault does not advance revision")
	var candidate: WorldState = service.get_world_snapshot()
	var frame := WorldFrame.new(1, candidate.player_position, false, false)
	var runtime: Dictionary = service.commit_runtime_step(1, WorldStepResult.new(candidate, frame), {"phase": SessionPhase.Phase.ACTION}, {"simulation_tick": 0})
	_check(runtime.get("ok") == false and runtime.errors[0].code == "SYNC_ACTIVATION_FAILED", "activation fault also locks runtime commits")
	view.queue_free()
	await _tree().process_frame
	return true


func _make_runtime(data: WorldState, adapter: WorldSyncAdapter = null, rules: SessionRules = null) -> Dictionary:
	var view := _make_view(data)
	var sync: WorldSyncAdapter = adapter if adapter != null else SceneWorldSyncAdapter.new(view)
	var service := WorldCommandService.new(data, _command_policy(), sync)
	var session := GameSession.new(SessionRules.new(2, 2) if rules == null else rules)
	var runtime := GameRuntime.new()
	_tree().root.add_child(runtime)
	runtime.auto_advance = false
	runtime.configure(service, session, view, _rules())
	return {"runtime": runtime, "view": view, "service": service, "session": session}


func _runtime_cycle() -> bool:
	var bundle: Dictionary = _make_runtime(_view_world())
	var runtime: GameRuntime = bundle.runtime
	var service: WorldCommandService = bundle.service
	var session: GameSession = bundle.session
	var first: Dictionary = runtime.step_once(Vector2.RIGHT, 1.0 / 60.0)
	_check(first.get("ok") == true and first.tick == 1, "runtime commits first physics step")
	_check(service.get_world_snapshot().player_position.x > 96.0, "runtime writes actual player movement")
	_check(service.get_world_snapshot().validate().is_empty(), "world remains valid after integrated motion")
	_check(runtime.step_once(Vector2.ZERO, 1.0 / 60.0).get("ok") == true, "first report boundary returns to action")
	_check(runtime.step_once(Vector2.ZERO, 1.0 / 60.0).get("ok") == true, "runtime advances third tick")
	var fourth: Dictionary = runtime.step_once(Vector2.ZERO, 1.0 / 60.0)
	_check(fourth.get("ok") == true and fourth.tick == 4, "guess boundary completes report processing")
	_check(session.get_state_snapshot().phase == SessionPhase.Phase.GUESS_PAUSED, "runtime enters guess pause at configured boundary")
	_check(session.get_cycle_snapshot().simulation_tick == 4, "clock freezes at guess pause")
	var rejected: Dictionary = runtime.step_once(Vector2.ZERO, 1.0 / 60.0)
	_check(rejected.get("ok") == false and session.get_cycle_snapshot().simulation_tick == 4, "paused step does not advance world or clock")
	_check(runtime.get_fault().is_empty(), "valid runtime cycle has no fault")
	bundle.runtime.queue_free()
	bundle.view.queue_free()
	await _tree().process_frame
	return true


func _runtime_fault_lock() -> bool:
	var data := _view_world()
	var view := _make_view(data)
	var service := WorldCommandService.new(data, _command_policy(), FailingSceneAdapter.new(view))
	var failed_deploy: WorldCommandResult = _commit(service, [{"type": "AddDevice", "device": {"kind": "pressure_plate", "cell": [3, 3], "parameters": {}}}], 0)
	_check(failed_deploy.status == "REJECTED", "fault fixture activates service lock")
	var session := GameSession.new(SessionRules.new(2, 2))
	var runtime := GameRuntime.new()
	_tree().root.add_child(runtime)
	runtime.auto_advance = false
	runtime.configure(service, session, view, _rules())
	var result: Dictionary = runtime.step_once(Vector2.ZERO, 1.0 / 60.0)
	_check(result.get("ok") == false and not runtime.get_fault().is_empty(), "runtime exposes commit fault")
	_check(session.get_cycle_snapshot().simulation_tick == 0, "fault prevents GameSession advancement")
	runtime.queue_free()
	view.queue_free()
	await _tree().process_frame
	return true


func _runtime_push_world_consistency() -> bool:
	var bundle: Dictionary = _make_runtime(_view_world(), null, SessionRules.new(100, 100))
	var runtime: GameRuntime = bundle.runtime
	var view: RuntimeWorldView = bundle.view
	var service: WorldCommandService = bundle.service
	view.get_player().global_position = Vector2(130, 224)
	var player_start: Vector2 = view.get_player().global_position
	for _i: int in 60:
		await _tree().physics_frame
		var result: Dictionary = await runtime.step_once(Vector2.ZERO, 1.0 / 60.0)
		_check(result.get("ok") == true, "runtime push consistency step accepted")
		_check(view.get_player().global_position.is_equal_approx(service.get_world_snapshot().player_position), "pushed player node and committed world match in same physics step")
	_check(view.get_player().global_position.x > player_start.x + 5.0, "integrated runtime actually pushes player")
	runtime.queue_free()
	view.queue_free()
	await _tree().process_frame
	return true


func _runtime_stays_action() -> bool:
	var data: WorldState = LevelTemplate.from_data(PrototypeConfig.level_data()).instantiate_world()
	var bundle: Dictionary = _make_runtime(data, null, PrototypeConfig.make_session_rules())
	var runtime: GameRuntime = bundle.runtime
	var session: GameSession = bundle.session
	for _i: int in 120:
		await _tree().physics_frame
		await runtime.step_once(Vector2.ZERO, 1.0 / 60.0)
	_check(session.get_state_snapshot().phase == SessionPhase.Phase.ACTION, "graybox remains interactive beyond unsupported guess boundary")
	_check(session.get_cycle_snapshot().simulation_tick == 120, "graybox fixture continues advancing physics ticks")
	runtime.queue_free()
	bundle.view.queue_free()
	await _tree().process_frame
	return true


func _prepare_failure_discards_nodes() -> bool:
	var data := _view_world()
	var view := TrackingWorldView.new()
	_tree().root.add_child(view)
	view.build_from_world(data)
	view.created_nodes.clear()
	var adapter := SceneWorldSyncAdapter.new(view)
	var result: Dictionary = adapter.prepare(data.to_snapshot(), data.to_snapshot(), {"terrain_changed": true, "changed_ids": [1, 999999], "removed_ids": []})
	_check(result.get("ok") == false, "prepare rejects unknown ID after staged work")
	_check(view.created_nodes.size() >= 2, "prepare failure fixture created staged resources")
	for node: Node in view.created_nodes:
		_check(not is_instance_valid(node), "failed prepare frees staged node")
	view.queue_free()
	await _tree().process_frame
	return true


func _player_cannot_push_robot() -> bool:
	var data := _patrol_world([[1, 1]])
	var world := _make_world()
	var player := _make_player(world, Vector2(100, 150))
	var robot := _make_robot(world, 1, Vector2(150, 150))
	await _settle()
	for _i: int in 90:
		await _tree().physics_frame
		player.advance(Vector2.RIGHT, 1.0 / 60.0, _rules())
	_check(robot.global_position.is_equal_approx(Vector2(150, 150)), "player cannot push stationary robot")
	_check(player.global_position.x < robot.global_position.x, "player is blocked by stationary robot")
	await _free_world(world)
	return true


func _robot_real_patrol() -> bool:
	var single_data := _patrol_world([[1, 1]])
	var single_entity: Dictionary = single_data.registry.get_entity(1)
	var single_world := _make_world()
	var single_player := _make_player(single_world, Vector2(350, 350))
	var single_robot := _make_robot(single_world, 1, Vector2(150, 150))
	await _settle()
	for _i: int in 30:
		await _tree().physics_frame
		single_entity.runtime_state = single_robot.advance(single_entity, single_data, single_player, 1.0 / 60.0)
	_check(single_robot.global_position.is_equal_approx(Vector2(150, 150)), "real robot remains stationary for single point route")
	await _free_world(single_world)

	var data := _patrol_world([[1, 1], [2, 1]])
	var entity: Dictionary = data.registry.get_entity(1)
	var world := _make_world()
	var player := _make_player(world, Vector2(350, 350))
	var robot := _make_robot(world, 1, Vector2(150, 150))
	await _settle()
	for _i: int in 90:
		await _tree().physics_frame
		entity.runtime_state = robot.advance(entity, data, player, 1.0 / 60.0)
	_check(robot.global_position.distance_to(Vector2(200, 150)) < 2.0, "real robot reverses through endpoint without teleport")
	_check(entity.runtime_state.travel_direction == -1, "real robot runtime state records reversal")
	await _free_world(world)

	var transition_data := _patrol_world([[1, 1], [2, 1]])
	var transition_entity: Dictionary = transition_data.registry.get_entity(1)
	transition_entity.patrol_path = [[1, 1], [1, 2]]
	transition_entity.runtime_state = {"position": [225.0, 150.0], "path_index": 0, "progress": 0.0, "travel_direction": 1, "transition": {"from_cell": [2, 1], "to_cell": [1, 1], "progress": 0.25}}
	var transition_world := _make_world()
	var transition_player := _make_player(transition_world, Vector2(350, 350))
	var transition_robot := _make_robot(transition_world, 1, Vector2(225, 150))
	await _settle()
	for _i: int in 60:
		await _tree().physics_frame
		transition_entity.runtime_state = transition_robot.advance(transition_entity, transition_data, transition_player, 1.0 / 60.0)
	_check(transition_entity.runtime_state.transition.is_empty(), "real robot completes transition into new route")
	_check(transition_robot.global_position.distance_to(Vector2(150, 175)) < 2.0, "real robot continues remaining motion after transition")
	await _free_world(transition_world)
	return true


func _all_phases_freeze() -> bool:
	var bundle: Dictionary = _make_runtime(_view_world(), null, SessionRules.new(100, 100))
	var runtime: GameRuntime = bundle.runtime
	var session: GameSession = bundle.session
	var service: WorldCommandService = bundle.service
	await runtime.step_once(Vector2.ZERO, 1.0 / 60.0)
	var frozen_world: Dictionary = service.get_world_snapshot().to_snapshot()
	var frozen_tick: int = session.get_cycle_snapshot().simulation_tick
	for phase: int in [SessionPhase.Phase.CONTACT_PAUSED, SessionPhase.Phase.DISPATCH_PAUSED, SessionPhase.Phase.CYCLE_START_PENDING, SessionPhase.Phase.ROUND_END]:
		session._state.phase = phase
		var result: Dictionary = await runtime.step_once(Vector2.RIGHT, 1.0 / 60.0)
		_check(result.get("ok") == false, "paused phase rejects motion: %d" % phase)
		_check(session.get_cycle_snapshot().simulation_tick == frozen_tick, "paused phase freezes clock: %d" % phase)
		_check(service.get_world_snapshot().to_snapshot() == frozen_world, "paused phase freezes world: %d" % phase)
	runtime.queue_free()
	bundle.view.queue_free()
	await _tree().process_frame
	return true


func _interaction_world() -> WorldState:
	var terrain: Array = []
	for y: int in 6:
		var row: Array = []
		for x: int in 8:
			row.append("WALL" if x == 0 or y == 0 or x == 7 or y == 5 else "FLOOR")
		terrain.append(row)
	return LevelTemplate.from_data({
		"template_key": "interaction_scene_test", "grid_size": [8, 6], "cell_size": 64.0, "origin": [0.0, 0.0],
		"terrain": terrain, "player_spawn": [96.0, 96.0], "device_rules": _device_rules(),
		"initial_entities": [
			{"kind": "camera", "cell": [2, 1], "mount_type": "ceiling", "parameters": {"enabled": true, "view_radius": 384.0, "fov_angle": 1.0, "scan_center": 0.0, "scan_half_angle": 0.5, "scan_speed": 1.0}},
			{"kind": "robot", "cell": [1, 3], "parameters": {"view_radius": 384.0, "move_speed": 64.0}, "patrol_path": [[1, 3], [2, 3]]},
			{"kind": "goal", "cell": [4, 2], "parameters": {}},
			{"kind": "goal", "cell": [5, 2], "parameters": {}},
			{"kind": "contact", "cell": [1, 4], "parameters": {}},
			{"kind": "exit", "cell": [6, 4], "parameters": {}},
		],
	}).instantiate_world()


func _interaction_fixture() -> bool:
	var data := _interaction_world()
	_check(data != null and data.validate().is_empty(), "two-goal interaction fixture is valid")
	_check(data.registry.to_snapshot().size() == 6, "fixture contains camera, robot, two goals, contact and exit")
	var view := _make_view(data)
	await _settle()
	for id: int in [1, 2, 3, 4, 5, 6]:
		_check(view.get_entity_node(id) != null, "interaction fixture entity node exists: %d" % id)
	var goal_position: Vector2 = view.get_entity_node(3).global_position
	var contact_position: Vector2 = view.get_entity_node(5).global_position
	_check(goal_position.distance_to(contact_position) > 128.0, "goal and contact interaction zones do not overlap")
	view.queue_free()
	await _tree().process_frame
	return true


func _goal_operation() -> bool:
	var bundle: Dictionary = _make_runtime(_interaction_world(), null, SessionRules.new(100, 100))
	var runtime: GameRuntime = bundle.runtime
	var view: RuntimeWorldView = bundle.view
	var service: WorldCommandService = bundle.service
	var session: GameSession = bundle.session
	view.get_player().global_position = Vector2(250, 160)
	await runtime.step_once(Vector2.ZERO, 1.0 / 60.0, true)
	var goal: Dictionary = service.get_world_snapshot().registry.get_entity(3)
	_check(goal.runtime_state.active and goal.runtime_state.progress > 0.0, "nearby interact starts goal progress")
	var events: Array[Dictionary] = runtime.get_last_domain_events()
	_check(events.size() == 1 and events[0].type == "GOAL_OPERATION_STARTED" and events[0].progress == 0.0, "goal start emits one accurate event")
	var progress: float = goal.runtime_state.progress
	await runtime.step_once(Vector2.ZERO, 1.0 / 60.0)
	_check(service.get_world_snapshot().registry.get_entity(3).runtime_state.progress > progress, "stationary goal progress advances")
	await runtime.step_once(Vector2.RIGHT, 1.0 / 60.0)
	goal = service.get_world_snapshot().registry.get_entity(3)
	_check(not goal.runtime_state.active and goal.runtime_state.progress == 0.0, "direction input cancels and clears goal progress")
	events = runtime.get_last_domain_events()
	_check(events.size() == 1 and events[0].type == "GOAL_OPERATION_CANCELLED" and events[0].progress > 0.0, "cancel event preserves pre-reset progress")

	view.get_player().global_position = Vector2(250, 160)
	await runtime.step_once(Vector2.ZERO, 1.0 / 60.0, true)
	progress = service.get_world_snapshot().registry.get_entity(3).runtime_state.progress
	session._state.phase = SessionPhase.Phase.GUESS_PAUSED
	var paused: Dictionary = await runtime.step_once(Vector2.ZERO, 1.0 / 60.0)
	_check(paused.get("ok") == false and service.get_world_snapshot().registry.get_entity(3).runtime_state.progress == progress, "guess pause freezes goal without cancelling")
	session._state.phase = SessionPhase.Phase.ACTION
	await runtime.step_once(Vector2.ZERO, 1.0 / 60.0)
	_check(service.get_world_snapshot().registry.get_entity(3).runtime_state.progress > progress, "goal resumes after guess pause")
	view.get_player().global_position = Vector2(96, 96)
	await runtime.step_once(Vector2.ZERO, 1.0 / 60.0)
	goal = service.get_world_snapshot().registry.get_entity(3)
	_check(not goal.runtime_state.active and goal.runtime_state.progress == 0.0, "leaving interaction area cancels goal")
	_check(service.get_world_snapshot().registry.get_entity(4).runtime_state.progress == 0.0, "second goal state remains independent")
	runtime.queue_free()
	view.queue_free()
	await _tree().process_frame
	return true


func _goal_completion_all() -> bool:
	var bundle: Dictionary = _make_runtime(_interaction_world(), null, SessionRules.new(100, 100))
	var runtime: GameRuntime = bundle.runtime
	var view: RuntimeWorldView = bundle.view
	var service: WorldCommandService = bundle.service
	view.get_player().global_position = Vector2(250, 160)
	await runtime.step_once(Vector2.ZERO, 1.0 / 60.0, true)
	for _i: int in 119:
		await runtime.step_once(Vector2.ZERO, 1.0 / 60.0)
	_check(service.get_world_snapshot().registry.get_entity(3).runtime_state.complete, "first goal completes after configured duration")
	_check(not service.get_world_snapshot().registry.get_entity(4).runtime_state.complete, "second goal remains incomplete")
	_check(not view.last_interaction.goal_complete, "one of two goals does not satisfy all-goals completion")
	view.get_player().global_position = Vector2(390, 160)
	await runtime.step_once(Vector2.ZERO, 1.0 / 60.0, true)
	for _i: int in 119:
		await runtime.step_once(Vector2.ZERO, 1.0 / 60.0)
	_check(service.get_world_snapshot().registry.get_entity(4).runtime_state.complete, "second goal completes independently")
	_check(view.last_interaction.goal_complete, "all goals complete satisfies goal completion")
	var events: Array[Dictionary] = runtime.get_last_domain_events()
	_check(events.size() == 1 and events[0].type == "GOAL_OPERATION_COMPLETED", "goal completion emits one completed event")
	await runtime.step_once(Vector2.ZERO, 1.0 / 60.0)
	_check(runtime.get_last_domain_events().is_empty(), "completed goal does not duplicate events")
	runtime.queue_free()
	view.queue_free()
	await _tree().process_frame
	return true


func _contact_flow() -> bool:
	var bundle: Dictionary = _make_runtime(_interaction_world(), null, SessionRules.new(100, 100))
	var runtime: GameRuntime = bundle.runtime
	var view: RuntimeWorldView = bundle.view
	var service: WorldCommandService = bundle.service
	var session: GameSession = bundle.session
	view.get_player().global_position = Vector2(140, 288)
	await runtime.step_once(Vector2.ZERO, 1.0 / 60.0, true)
	_check(session.get_state_snapshot().phase == SessionPhase.Phase.CONTACT_PAUSED, "nearby unused contact starts contact pause")
	_check(service.get_world_snapshot().registry.get_entity(5).runtime_state.used, "successful contact start consumes contact")
	_check(runtime.get_active_contact_id() == 5, "runtime records trusted active contact ID")
	var rejected: bool = session.end_contact(func(_expected: Dictionary) -> WorldCommandResult: return WorldCommandResult.new())
	_check(not rejected and session.get_state_snapshot().phase == SessionPhase.Phase.CONTACT_PAUSED, "invalid deployment cannot leave contact pause")
	_check(service.get_world_snapshot().registry.get_entity(5).runtime_state.used, "invalid deployment does not refund contact")
	_check(runtime.keep_current(), "explicit keep current exits contact")
	_check(session.get_state_snapshot().phase == SessionPhase.Phase.ACTION and runtime.get_active_contact_id() == 0, "keep current restores action and clears active contact")
	_check(service.get_world_snapshot().registry.get_entity(5).runtime_state.used, "keep current does not refund contact")
	await runtime.step_once(Vector2.ZERO, 1.0 / 60.0, true)
	_check(session.get_state_snapshot().phase == SessionPhase.Phase.ACTION, "used contact cannot start another session")
	view.get_player().global_position = Vector2(96, 96)
	await runtime.step_once(Vector2.ZERO, 1.0 / 60.0, true)
	_check(session.get_state_snapshot().phase == SessionPhase.Phase.ACTION, "remote contact request is ignored")
	runtime.queue_free()
	view.queue_free()
	await _tree().process_frame
	return true


func _contact_boundary_priority() -> bool:
	var guess_bundle: Dictionary = _make_runtime(_interaction_world(), null, SessionRules.new(1, 1))
	guess_bundle.view.get_player().global_position = Vector2(140, 288)
	await guess_bundle.runtime.step_once(Vector2.ZERO, 1.0 / 60.0, true)
	_check(guess_bundle.session.get_state_snapshot().phase == SessionPhase.Phase.GUESS_PAUSED, "guess boundary wins over contact request")
	_check(not guess_bundle.service.get_world_snapshot().registry.get_entity(5).runtime_state.used, "guess priority does not consume contact")
	_check(guess_bundle.runtime.get_active_contact_id() == 0, "guess priority leaves no active contact")
	guess_bundle.runtime.queue_free()
	guess_bundle.view.queue_free()
	await _tree().process_frame

	var report_bundle: Dictionary = _make_runtime(_interaction_world(), null, SessionRules.new(1, 2))
	report_bundle.view.get_player().global_position = Vector2(140, 288)
	await report_bundle.runtime.step_once(Vector2.ZERO, 1.0 / 60.0, true)
	_check(report_bundle.session.get_state_snapshot().phase == SessionPhase.Phase.CONTACT_PAUSED, "ordinary report completes before contact starts")
	_check(report_bundle.service.get_world_snapshot().registry.get_entity(5).runtime_state.used, "ordinary report contact consumes once")
	report_bundle.runtime.queue_free()
	report_bundle.view.queue_free()
	await _tree().process_frame
	return true


func _complete_goal_for_exit(runtime: GameRuntime, view: RuntimeWorldView, position: Vector2) -> void:
	view.get_player().global_position = position
	await runtime.step_once(Vector2.ZERO, 1.0 / 60.0, true)
	for _i: int in 119:
		await runtime.step_once(Vector2.ZERO, 1.0 / 60.0)


func _exit_completion() -> bool:
	var bundle: Dictionary = _make_runtime(_interaction_world(), null, SessionRules.new(100, 100))
	var runtime: GameRuntime = bundle.runtime
	var view: RuntimeWorldView = bundle.view
	var session: GameSession = bundle.session
	view.get_player().global_position = Vector2(350, 288)
	await _tree().physics_frame
	for _i: int in 60:
		await runtime.step_once(Vector2.RIGHT, 1.0 / 60.0)
	_check(view.last_interaction.at_exit, "real exit collision produces at_exit")
	_check(not view.last_interaction.goal_complete, "exit contact does not bypass incomplete goals")
	_check(session.get_state_snapshot().phase == SessionPhase.Phase.ACTION, "incomplete goals prevent round success at exit")
	await _complete_goal_for_exit(runtime, view, Vector2(250, 160))
	await _complete_goal_for_exit(runtime, view, Vector2(390, 160))
	view.get_player().global_position = Vector2(350, 288)
	await _tree().physics_frame
	for _i: int in 60:
		if session.get_state_snapshot().phase == SessionPhase.Phase.ACTION:
			await runtime.step_once(Vector2.RIGHT, 1.0 / 60.0)
	_check(session.get_state_snapshot().phase == SessionPhase.Phase.ROUND_END, "all goals and real exit contact end round")
	_check(session.get_state_snapshot().round_result == SessionPhase.RoundResult.SUCCESS, "exit produces successful round result")
	var final_tick: int = session.get_cycle_snapshot().simulation_tick
	var repeated: Dictionary = await runtime.step_once(Vector2.RIGHT, 1.0 / 60.0)
	_check(repeated.get("ok") == false and session.get_cycle_snapshot().simulation_tick == final_tick, "round end does not repeatedly settle exit contact")
	runtime.queue_free()
	view.queue_free()
	await _tree().process_frame
	return true


func _contact_successful_retry() -> bool:
	var bundle: Dictionary = _make_runtime(_interaction_world(), null, SessionRules.new(100, 100))
	var runtime: GameRuntime = bundle.runtime
	var view: RuntimeWorldView = bundle.view
	var service: WorldCommandService = bundle.service
	var session: GameSession = bundle.session
	view.get_player().global_position = Vector2(140, 288)
	await runtime.step_once(Vector2.ZERO, 1.0 / 60.0, true)
	var rejected: bool = session.end_contact(func(_expected: Dictionary) -> WorldCommandResult: return WorldCommandResult.new())
	_check(not rejected and session.get_state_snapshot().phase == SessionPhase.Phase.CONTACT_PAUSED, "invalid proposal precedes successful retry in same session")
	_check(session.renew_world_request() != {}, "rejected contact proposal can be replaced with a new request")
	var ended: bool = session.end_contact(func(expected: Dictionary) -> WorldCommandResult:
		var batch := WorldCommandBatch.from_data({"context": AgentProtocol.serialize_context(expected), "source": "contact", "base_world_revision": service.get_world_snapshot().world_revision, "mode": "APPLY", "commands": [{"type": "SetDeviceParameter", "id": 1, "parameter": "scan_center", "value": 0.2}]})
		return service.commit_batch(batch, expected)
	)
	_check(ended and session.get_state_snapshot().phase == SessionPhase.Phase.ACTION, "valid replacement deployment ends contact")
	_check(runtime.get_active_contact_id() == 0, "successful external deployment clears active contact ID")
	_check(service.get_world_snapshot().registry.get_entity(5).runtime_state.used, "successful deployment does not refund contact")
	_check(service.get_world_snapshot().registry.get_entity(1).parameters.scan_center == 0.2, "valid contact deployment applies camera change")
	runtime.queue_free()
	view.queue_free()
	await _tree().process_frame
	return true


func _goal_input_validation() -> bool:
	var bundle: Dictionary = _make_runtime(_interaction_world(), null, SessionRules.new(100, 100))
	var runtime: GameRuntime = bundle.runtime
	var view: RuntimeWorldView = bundle.view
	var service: WorldCommandService = bundle.service
	var session: GameSession = bundle.session
	view.get_player().global_position = Vector2(96, 96)
	await runtime.step_once(Vector2.ZERO, 1.0 / 60.0, true)
	_check(not service.get_world_snapshot().registry.get_entity(3).runtime_state.active, "remote goal cannot start")
	view.get_player().global_position = Vector2(250, 160)
	await runtime.step_once(Vector2.RIGHT, 1.0 / 60.0, true)
	_check(not service.get_world_snapshot().registry.get_entity(3).runtime_state.active, "direction input prevents new goal start")
	view.get_player().global_position = Vector2(250, 160)
	view.get_player().velocity = Vector2.ZERO
	await runtime.step_once(Vector2.ZERO, 1.0 / 60.0, true, true)
	_check(not service.get_world_snapshot().registry.get_entity(3).runtime_state.active, "simultaneous cancel prevents new goal start")
	_check(runtime.get_last_domain_events().is_empty(), "simultaneous cancel does not emit goal noise")
	view.get_player().global_position = Vector2(250, 160)
	await runtime.step_once(Vector2.ZERO, 1.0 / 60.0, true)
	await runtime.step_once(Vector2.ZERO, 1.0 / 60.0, false, true)
	_check(not service.get_world_snapshot().registry.get_entity(3).runtime_state.active, "explicit cancel input stops goal")
	_check(service.get_world_snapshot().registry.get_entity(3).runtime_state.progress == 0.0, "explicit cancel clears progress")
	view.get_player().global_position = Vector2(250, 160)
	await runtime.step_once(Vector2.ZERO, 1.0 / 60.0, true)
	var progress: float = service.get_world_snapshot().registry.get_entity(3).runtime_state.progress
	session._state.phase = SessionPhase.Phase.CONTACT_PAUSED
	await runtime.step_once(Vector2.ZERO, 1.0 / 60.0)
	_check(service.get_world_snapshot().registry.get_entity(3).runtime_state.progress == progress, "contact pause freezes active goal")
	session._state.phase = SessionPhase.Phase.ACTION
	await runtime.step_once(Vector2.ZERO, 1.0 / 60.0)
	_check(service.get_world_snapshot().registry.get_entity(3).runtime_state.progress > progress, "goal resumes after contact pause")
	runtime.queue_free()
	view.queue_free()
	await _tree().process_frame
	return true


func _goal_robot_push_cancel() -> bool:
	var data := _interaction_world()
	var goal: Dictionary = data.registry.get_entity(3)
	goal.cell = [1, 2]
	data.registry._put(goal)
	var bundle: Dictionary = _make_runtime(data, null, SessionRules.new(100, 100))
	var runtime: GameRuntime = bundle.runtime
	var view: RuntimeWorldView = bundle.view
	var service: WorldCommandService = bundle.service
	view.get_player().global_position = Vector2(120, 210)
	await runtime.step_once(Vector2.ZERO, 1.0 / 60.0, true)
	var saw_cancel: bool = false
	for _i: int in 80:
		await _tree().physics_frame
		await runtime.step_once(Vector2.ZERO, 1.0 / 60.0)
		for event: Dictionary in runtime.get_last_domain_events():
			saw_cancel = saw_cancel or event.type == "GOAL_OPERATION_CANCELLED"
	_check(view.get_player().global_position.x > 140.0, "robot physically pushes player during goal operation")
	_check(saw_cancel, "robot push out emits goal cancellation")
	_check(not service.get_world_snapshot().registry.get_entity(3).runtime_state.active, "robot push out stops goal")
	runtime.queue_free()
	view.queue_free()
	await _tree().process_frame
	return true


func _domain_event_boundary() -> bool:
	var bundle: Dictionary = _make_runtime(_interaction_world(), null, SessionRules.new(1, 2))
	var runtime: GameRuntime = bundle.runtime
	var view: RuntimeWorldView = bundle.view
	var session: GameSession = bundle.session
	view.get_player().global_position = Vector2(250, 160)
	await runtime.step_once(Vector2.ZERO, 1.0 / 60.0, true)
	var events: Array[Dictionary] = runtime.get_last_domain_events()
	_check(events.size() == 1 and events[0].tick == 1, "goal event retains originating report-boundary tick")
	events[0].progress = 0.9
	_check(runtime.get_last_domain_events()[0].progress == 0.0, "domain event consumers receive deep copies")
	await runtime.step_once(Vector2.ZERO, 1.0 / 60.0)
	_check(session.get_state_snapshot().phase == SessionPhase.Phase.GUESS_PAUSED, "event fixture reaches guess boundary")
	_check(runtime.get_last_domain_events().is_empty(), "guess boundary does not duplicate goal start event")
	runtime.queue_free()
	view.queue_free()
	await _tree().process_frame
	return true


func _exit_guess_priority() -> bool:
	var bundle: Dictionary = _make_runtime(_interaction_world(), null, SessionRules.new(100, 100))
	var runtime: GameRuntime = bundle.runtime
	var view: RuntimeWorldView = bundle.view
	var session: GameSession = bundle.session
	await _complete_goal_for_exit(runtime, view, Vector2(250, 160))
	await _complete_goal_for_exit(runtime, view, Vector2(390, 160))
	session._rules = SessionRules.new(1, 1)
	view.get_player().global_position = Vector2(374, 288)
	await _tree().physics_frame
	for _i: int in 60:
		if session.get_state_snapshot().phase == SessionPhase.Phase.ACTION:
			await runtime.step_once(Vector2.RIGHT, 1.0 / 60.0)
	_check(session.get_state_snapshot().phase == SessionPhase.Phase.GUESS_PAUSED, "exit and guess boundary require guess before round result")
	var frozen: Dictionary = session.get_state_snapshot().frozen_guess_frame
	_check(frozen.get("goal_complete", false) and frozen.get("at_exit", false), "guess freezes completed goal and exit conditions")
	runtime.queue_free()
	view.queue_free()
	await _tree().process_frame
	return true


func _goal_residual_velocity_cancel() -> bool:
	var bundle: Dictionary = _make_runtime(_interaction_world(), null, SessionRules.new(100, 100))
	var runtime: GameRuntime = bundle.runtime
	var view: RuntimeWorldView = bundle.view
	var service: WorldCommandService = bundle.service
	view.get_player().global_position = Vector2(250, 160)
	await runtime.step_once(Vector2.ZERO, 1.0 / 60.0, true)
	view.get_player().velocity = Vector2(-300, 0)
	var saw_cancel: bool = false
	for _i: int in 12:
		await _tree().physics_frame
		await runtime.step_once(Vector2.ZERO, 1.0 / 60.0)
		for event: Dictionary in runtime.get_last_domain_events():
			saw_cancel = saw_cancel or event.type == "GOAL_OPERATION_CANCELLED"
	_check(view.get_player().global_position.x < 250.0, "residual velocity moves player without direction input")
	_check(saw_cancel, "residual velocity leaving interaction area cancels goal")
	_check(not service.get_world_snapshot().registry.get_entity(3).runtime_state.active, "residual movement stops active goal")
	runtime.queue_free()
	view.queue_free()
	await _tree().process_frame
	return true


func _contact_input_keep_current() -> bool:
	var bundle: Dictionary = _make_runtime(_interaction_world(), null, SessionRules.new(100, 100))
	var runtime: GameRuntime = bundle.runtime
	var view: RuntimeWorldView = bundle.view
	var session: GameSession = bundle.session
	view.get_player().global_position = Vector2(140, 288)
	await runtime.step_once(Vector2.ZERO, 1.0 / 60.0, true)
	runtime.auto_advance = true
	Input.action_press("interact")
	runtime._physics_process(1.0 / 60.0)
	Input.action_release("interact")
	runtime.auto_advance = false
	_check(session.get_state_snapshot().phase == SessionPhase.Phase.ACTION, "interact input path exits contact with keep current")
	_check(runtime.get_active_contact_id() == 0, "input recovery clears active contact")
	runtime.queue_free()
	view.queue_free()
	await _tree().process_frame
	return true


func _contact_success_priority() -> bool:
	var data := _interaction_world()
	var view := ForcedInteractionView.new()
	_tree().root.add_child(view)
	view.build_from_world(data)
	view.forced_interaction = {"events": [], "goal_complete": true, "at_exit": true, "contact_requested": true, "contact_id": 5, "errors": []}
	var service := WorldCommandService.new(data, _command_policy(), SceneWorldSyncAdapter.new(view))
	var session := GameSession.new(SessionRules.new(100, 100))
	var runtime := GameRuntime.new()
	_tree().root.add_child(runtime)
	runtime.auto_advance = false
	runtime.configure(service, session, view, _rules())
	await runtime.step_once(Vector2.ZERO, 1.0 / 60.0, true)
	_check(session.get_state_snapshot().phase == SessionPhase.Phase.ROUND_END, "round success wins over simultaneous contact request")
	_check(not service.get_world_snapshot().registry.get_entity(5).runtime_state.used, "successful round does not consume simultaneous contact")
	_check(runtime.get_active_contact_id() == 0, "successful round does not retain active contact")
	runtime.queue_free()
	view.queue_free()
	await _tree().process_frame
	return true
