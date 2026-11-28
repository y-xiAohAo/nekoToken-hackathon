extends RefCounted
class_name RuntimeMotionTests


var passed: int = 0
var failed: int = 0


func run() -> Dictionary:
	for scenario: Callable in [_runtime_step_commit, _camera_motion, _patrol_motion, _goal_state_schema]:
		_check(scenario.call() == true, "scenario completed: " + scenario.get_method())
	return {"passed": passed, "failed": failed}


func _check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		push_error("RUNTIME MOTION TEST FAILED: " + label)


func _rules() -> Dictionary:
	return {
		"parameter_ranges": {
			"camera": {"view_radius": [0.1, 20.0], "fov_angle": [0.1, TAU], "scan_center": [-PI, PI], "scan_half_angle": [0.0, PI], "scan_speed": [0.0, 4.0]},
			"robot": {"view_radius": [0.1, 20.0], "move_speed": [0.1, 4.0]},
		},
		"camera_mount_limits": {"wall": {"half_angle": PI / 2.0}, "ceiling": {"center": 0.0, "half_angle": PI}},
		"camera_per_anchor": 1,
	}


func _world() -> WorldState:
	var terrain: Array = []
	for y: int in 4:
		var row: Array = []
		for x: int in 4:
			row.append("WALL" if x == 0 or y == 0 or x == 3 or y == 3 else "FLOOR")
		terrain.append(row)
	return LevelTemplate.from_data({
		"template_key": "runtime_motion_test", "grid_size": [4, 4], "cell_size": 1.0, "origin": [0.0, 0.0],
		"terrain": terrain, "player_spawn": [1.5, 1.5], "device_rules": _rules(),
		"initial_entities": [{"kind": "camera", "cell": [2, 2], "mount_type": "ceiling", "parameters": {"enabled": true, "view_radius": 5.0, "fov_angle": 1.0, "scan_center": 0.0, "scan_half_angle": 0.5, "scan_speed": 1.0}}],
	}).instantiate_world()


func _commit(service: WorldCommandService, tick: int, candidate: WorldState, phase: int = SessionPhase.Phase.ACTION, current_tick: int = -1) -> Dictionary:
	var frame := WorldFrame.new(tick, candidate.player_position, false, false)
	var snapshot_tick: int = tick - 1 if current_tick < 0 else current_tick
	return service.commit_runtime_step(tick, WorldStepResult.new(candidate, frame), {"phase": phase}, {"simulation_tick": snapshot_tick})


func _runtime_step_commit() -> bool:
	var service := WorldCommandService.new(_world(), {}, WorldSyncAdapter.new())
	var candidate: WorldState = service.get_world_snapshot()
	candidate.player_position = Vector2(1.6, 1.5)
	var result: Dictionary = _commit(service, 1, candidate)
	_check(result.get("ok") == true, "valid runtime step accepted")
	_check(service.get_world_snapshot().player_position.is_equal_approx(Vector2(1.6, 1.5)), "actual player position committed")
	_check(service.get_world_snapshot().world_revision == 0, "motion does not advance deployment revision")
	candidate.player_position = Vector2(1.7, 1.5)
	_check(service.get_world_snapshot().player_position.is_equal_approx(Vector2(1.6, 1.5)), "caller cannot mutate committed world after return")

	var wrong_tick: Dictionary = _commit(service, 3, candidate, SessionPhase.Phase.ACTION, 1)
	_check(wrong_tick.get("ok") == false and wrong_tick.errors[0].code == "INVALID_TICK", "non-contiguous runtime tick rejected")
	var wrong_phase: Dictionary = _commit(service, 2, candidate, SessionPhase.Phase.GUESS_PAUSED)
	_check(wrong_phase.get("ok") == false and wrong_phase.errors[0].code == "INVALID_PHASE", "paused runtime step rejected")

	var changed_terrain: WorldState = service.get_world_snapshot()
	changed_terrain.terrain[1][1] = "WALL"
	var structure_result: Dictionary = _commit(service, 2, changed_terrain)
	_check(structure_result.get("ok") == false and structure_result.errors[0].code == "INVALID_WORLD", "runtime cannot change terrain")
	_check(service.get_world_snapshot().terrain[1][1] == "FLOOR", "rejected structure change leaves world intact")

	var changed_frame: WorldState = service.get_world_snapshot()
	var frame := WorldFrame.new(2, Vector2.ZERO, false, false)
	var frame_result: Dictionary = service.commit_runtime_step(2, WorldStepResult.new(changed_frame, frame), {"phase": SessionPhase.Phase.ACTION}, {"simulation_tick": 1})
	_check(frame_result.get("ok") == false and frame_result.errors[0].code == "INVALID_FRAME", "WorldFrame must match candidate position")

	var camera_state: WorldState = service.get_world_snapshot()
	var camera: Dictionary = camera_state.registry.get_entity(1)
	camera.runtime_state.heading = 0.25
	camera_state.registry._put(camera)
	var camera_result: Dictionary = _commit(service, 2, camera_state)
	_check(camera_result.get("ok") == true, "entity runtime state can advance")
	_check(service.get_world_snapshot().registry.get_entity(1).runtime_state.heading == 0.25, "camera heading committed")
	_check(service.get_world_snapshot().world_revision == 0, "entity motion still leaves revision unchanged")
	return true


func _camera_motion() -> bool:
	var entity: Dictionary = _world().registry.get_entity(1)
	var first: Dictionary = DeviceMotion.advance_camera(entity, 0.25)
	_check(is_equal_approx(first.heading, 0.25) and first.scan_direction == 1, "camera advances by simulation delta")
	entity.runtime_state = first
	var bounced: Dictionary = DeviceMotion.advance_camera(entity, 0.5)
	_check(is_equal_approx(bounced.heading, 0.25) and bounced.scan_direction == -1, "camera reverses at scan boundary with overshoot")
	entity.runtime_state = bounced
	entity.parameters.scan_speed = 0.0
	var stopped: Dictionary = DeviceMotion.advance_camera(entity, 1.0)
	_check(stopped == bounced, "zero scan speed preserves phase and direction")
	return true


func _robot_world(path: Array) -> WorldState:
	var terrain: Array = []
	for y: int in 4:
		var row: Array = []
		for x: int in 4:
			row.append("WALL" if x == 0 or y == 0 or x == 3 or y == 3 else "FLOOR")
		terrain.append(row)
	return LevelTemplate.from_data({
		"template_key": "patrol_motion_test", "grid_size": [4, 4], "cell_size": 1.0, "origin": [0.0, 0.0],
		"terrain": terrain, "player_spawn": [1.5, 2.5], "device_rules": _rules(),
		"initial_entities": [{"kind": "robot", "cell": path[0], "parameters": {"view_radius": 4.0, "move_speed": 1.0}, "patrol_path": path}],
	}).instantiate_world()


func _patrol_motion() -> bool:
	var world := _robot_world([[1, 1], [2, 1]])
	var entity: Dictionary = world.registry.get_entity(1)
	var first: Dictionary = DeviceMotion.patrol_target(entity, 0.25, world)
	_check(is_equal_approx(first.progress, 0.25), "patrol advances segment progress")
	_check(DeviceRegistry.vector(first.position).is_equal_approx(Vector2(1.75, 1.5)), "patrol uses continuous grid-center positions")
	entity.runtime_state = first
	var bounced: Dictionary = DeviceMotion.patrol_target(entity, 1.0, world)
	_check(bounced.path_index == 1 and bounced.travel_direction == -1, "patrol reverses at route endpoint")
	_check(is_equal_approx(bounced.progress, 0.25), "patrol carries remaining motion after endpoint")
	_check(DeviceRegistry.vector(bounced.position).is_equal_approx(Vector2(2.25, 1.5)), "patrol does not teleport at reversal")
	entity.runtime_state = bounced
	world.registry._put(entity)
	_check(world.validate().is_empty(), "continuous patrol state passes world validation")
	_check(world.snapshot_copy().registry.get_entity(1).runtime_state == bounced, "patrol runtime state survives snapshot")

	var single := _robot_world([[1, 1]])
	var single_entity: Dictionary = single.registry.get_entity(1)
	var stationary: Dictionary = DeviceMotion.patrol_target(single_entity, 2.0, single)
	_check(stationary.progress == 0.0 and DeviceRegistry.vector(stationary.position).is_equal_approx(Vector2(1.5, 1.5)), "single point route means stationary patrol")

	var transition_entity: Dictionary = world.registry.get_entity(1)
	transition_entity.patrol_path = [[1, 1], [1, 2]]
	transition_entity.runtime_state = {"position": [2.25, 1.5], "path_index": 0, "progress": 0.0, "travel_direction": 1, "transition": {"from_cell": [2, 1], "to_cell": [1, 1], "progress": 0.25}}
	world.registry._put(transition_entity)
	_check(world.validate().is_empty(), "unfinished transition is valid world state")
	var middle: Dictionary = DeviceMotion.patrol_target(transition_entity, 0.5, world)
	_check(is_equal_approx(middle.transition.progress, 0.75), "transition advances before new route")
	transition_entity.runtime_state = middle
	var joined: Dictionary = DeviceMotion.patrol_target(transition_entity, 0.5, world)
	_check(joined.transition.is_empty() and joined.path_index == 0, "completed transition joins new route")
	_check(is_equal_approx(joined.progress, 0.25) and DeviceRegistry.vector(joined.position).is_equal_approx(Vector2(1.5, 1.75)), "remaining motion continues into new route")
	transition_entity.runtime_state = joined
	world.registry._put(transition_entity)
	_check(world.validate().is_empty(), "joined route and position remain valid")
	return true


func _multi_goal_world() -> WorldState:
	var terrain: Array = []
	for y: int in 6:
		var row: Array = []
		for x: int in 8:
			row.append("WALL" if x == 0 or y == 0 or x == 7 or y == 5 else "FLOOR")
		terrain.append(row)
	return LevelTemplate.from_data({
		"template_key": "multi_goal_motion_test", "grid_size": [8, 6], "cell_size": 64.0, "origin": [0.0, 0.0],
		"terrain": terrain, "player_spawn": [96.0, 96.0], "device_rules": _rules(),
		"initial_entities": [
			{"kind": "goal", "cell": [4, 2], "parameters": {}},
			{"kind": "goal", "cell": [5, 2], "parameters": {}},
			{"kind": "contact", "cell": [1, 4], "parameters": {}},
			{"kind": "exit", "cell": [6, 4], "parameters": {}},
		],
	}).instantiate_world()


func _goal_state_schema() -> bool:
	var data := _multi_goal_world()
	_check(data != null, "multi-goal schema fixture instantiates")
	for id: int in [1, 2]:
		var state: Dictionary = data.registry.get_entity(id).runtime_state
		_check(state.has("active") and state.active == false, "goal starts inactive: %d" % id)
		_check(state.has("progress") and state.progress == 0.0, "goal has independent zero progress: %d" % id)
		_check(state.has("complete") and state.complete == false, "goal starts incomplete: %d" % id)
	var copied: WorldState = data.snapshot_copy()
	_check(copied != null, "goal runtime state survives snapshot")
	var active_goal: Dictionary = copied.registry.get_entity(1)
	active_goal.runtime_state = {"active": true, "progress": 0.4, "complete": false}
	copied.registry._put(active_goal)
	var completed_goal: Dictionary = copied.registry.get_entity(2)
	completed_goal.runtime_state = {"active": false, "progress": 1.0, "complete": true}
	copied.registry._put(completed_goal)
	var roundtrip: WorldState = copied.snapshot_copy()
	_check(roundtrip.registry.get_entity(1).runtime_state.active and roundtrip.registry.get_entity(1).runtime_state.progress == 0.4, "active goal progress survives snapshot independently")
	_check(roundtrip.registry.get_entity(2).runtime_state.complete, "second goal completion survives snapshot")

	var invalid_progress := _multi_goal_world()
	var goal: Dictionary = invalid_progress.registry.get_entity(1)
	goal.runtime_state.progress = 1.5
	invalid_progress.registry._put(goal)
	_check(not invalid_progress.validate().is_empty(), "goal progress above one rejected")
	goal.runtime_state = {"active": true, "progress": 1.0, "complete": true}
	invalid_progress.registry._put(goal)
	_check(not invalid_progress.validate().is_empty(), "active and complete combination rejected")
	goal.runtime_state = {"active": false, "progress": 0.5, "complete": true}
	invalid_progress.registry._put(goal)
	_check(not invalid_progress.validate().is_empty(), "complete goal requires full progress")
	goal.runtime_state = {"active": false, "progress": 0.999999, "complete": true}
	invalid_progress.registry._put(goal)
	_check(not invalid_progress.validate().is_empty(), "approximately full progress is not exact completion")

	var multiple_active := _multi_goal_world()
	for id: int in [1, 2]:
		var entity: Dictionary = multiple_active.registry.get_entity(id)
		entity.runtime_state.active = true
		multiple_active.registry._put(entity)
	_check(not multiple_active.validate().is_empty(), "two simultaneously active goals rejected")
	return true
