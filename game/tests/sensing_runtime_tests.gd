extends RefCounted
class_name SensingRuntimeTests
## Real scene and report-boundary contract checks for module 4B.

class FailingSealCoordinator extends RuntimeSensingCoordinator:
	func seal_report_batch(_boundary: ReportBoundary) -> bool:
		return false

class FailingViewCoordinator extends RuntimeSensingCoordinator:
	func update_system_view(_boundary: ReportBoundary, _committed_world: WorldState) -> bool:
		return false

class FailingPrepareCoordinator extends RuntimeSensingCoordinator:
	func prepare_step(_previous_actor_cells: Dictionary, _candidate: WorldState, _context: Dictionary) -> SensingStepResult:
		var result := SensingStepResult.new()
		result.errors.append({"code": "INJECTED_PREPARE"})
		return result

class FailingCommitCoordinator extends RuntimeSensingCoordinator:
	func commit_step(_prepared: SensingStepResult, _domain_events: Array[Dictionary], _committed_world: WorldState, _context: Dictionary) -> bool:
		return false

var passed: int = 0
var failed: int = 0

func run() -> Dictionary:
	_check(_dto_and_view(), "DTO and view scenario completed")
	_check(_coordinator_window(), "coordinator window scenario completed")
	_check(_coordinator_deployment(), "coordinator deployment scenario completed")
	_check(_new_robot_and_restart(), "new robot and restart sampling completed")
	_check(_simultaneous_plate(), "simultaneous anonymous plate scenario completed")
	_check(_terminal_half_batch(), "terminal half-batch scenario completed")
	_check(await _real_runtime(), "real runtime scenario completed")
	_check(await _real_completion(), "real completion scenario completed")
	_check(await _plate_reentry(), "real plate reentry scenario completed")
	_check(await _guess_pause(), "guess pause scenario completed")
	_check(await _fault_stops_runtime(), "fault scenario completed")
	_check(await _normal_multibatch(), "normal multibatch scenario completed")
	_check(await _random_multibatch(), "seeded multibatch scenario completed")
	return {"passed": passed, "failed": failed}

func _check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		push_error("SENSING RUNTIME FAILED: " + label)

func _context(tick: int, n: int) -> Dictionary:
	return {"round_id": 1, "branch_id": 1, "guess_cycle_id": 1,
		"report_cycle_id": tick / n + 1, "sense_tick": tick}

func _world() -> WorldState:
	return LevelTemplate.from_data(PrototypeConfig.level_data()).instantiate_world()

func _dto_and_view() -> bool:
	var world: WorldState = _world()
	_check(world != null and world.validate().is_empty(), "integer radius fixture is valid")
	var view := SystemAgentView.new()
	_check(view.initialize(world), "system view initializes")
	var data: Dictionary = view.to_data()
	_check(not data.has("player_position") and not data.world.has("player_position") and data.reports.is_empty(), "system view excludes hidden player position")
	data.world.cameras.clear()
	_check(not view.to_data().world.cameras.is_empty(), "system view read is detached")
	var invalid: Dictionary = view.snapshot()
	invalid["actor_id"] = 0
	_check(not view.restore(invalid) and not view.to_data().has("actor_id"), "forbidden field restore is atomic")
	invalid = view.snapshot()
	invalid.world.cameras[0].parameters.view_radius = "bad"
	_check(not view.restore(invalid), "invalid public configuration cannot restore")
	var goal: GoalOperationRecord = GoalOperationRecord.from_data({"round_id": 1, "branch_id": 1, "guess_cycle_id": 1, "report_cycle_id": 1,
		"goal_id": 4, "event_tick": 1, "type": "GOAL_OPERATION_STARTED"})
	_check(goal != null and goal.snapshot_copy().to_data() == goal.to_data(), "goal DTO roundtrip")
	var forbidden: Dictionary = goal.to_data()
	forbidden["progress"] = 0.5
	_check(GoalOperationRecord.from_data(forbidden) == null, "goal report rejects internal progress")
	var noninteger: Dictionary = PrototypeConfig.level_data()
	noninteger.initial_entities[0].parameters.view_radius = 300.0
	_check(LevelTemplate.from_data(noninteger).instantiate_world() == null, "noninteger radius rejected before runtime")
	return true

func _coordinator_window() -> bool:
	var world: WorldState = _world()
	var sensing := RuntimeSensingCoordinator.new()
	_check(sensing.initialize_round(world, _context(0, 3), 3), "tick zero coordinator initializes")
	_check(sensing.snapshot().device_buffer.pending.size() == 2, "tick zero has camera and robot observations")
	var unchanged: Dictionary = sensing.snapshot()
	var rejected_candidate: WorldState = world.snapshot_copy()
	var rejected_prepare: SensingStepResult = sensing.prepare_step(SensingKernel.actor_cells(world), rejected_candidate, _context(1, 3))
	var altered: SensingStepResult = rejected_prepare.snapshot_copy()
	altered.next_visual_states[1].last_evaluated_tick = 99
	_check(not sensing.commit_step(altered, [], rejected_candidate, _context(1, 3)) and sensing.snapshot() == unchanged, "altered prepared result cannot publish")
	rejected_prepare = sensing.prepare_step(SensingKernel.actor_cells(world), rejected_candidate, _context(1, 3))
	var bad_events: Array[Dictionary] = [{"goal_id": 4, "tick": 1, "type": "UNAUTHORIZED", "progress": 0.0}]
	_check(not sensing.commit_step(rejected_prepare, bad_events, rejected_candidate, _context(1, 3)) and sensing.snapshot() == unchanged, "invalid target event cannot publish sensing")
	var initial_view: Dictionary = sensing.get_system_view()
	for tick: int in [1, 2, 3]:
		var candidate: WorldState = world.snapshot_copy()
		if tick == 2:
			var camera: Dictionary = candidate.registry.get_entity(1)
			camera.parameters.enabled = false
			camera.runtime_state.heading = 0.25
			camera.runtime_state.scan_direction = -1
			candidate.registry._put(camera)
		var prepared: SensingStepResult = sensing.prepare_step(SensingKernel.actor_cells(world), candidate, _context(tick, 3))
		_check(prepared.succeeded(), "tick %d prepares" % tick)
		var events: Array[Dictionary] = []
		if tick == 2:
			events.append({"goal_id": 4, "tick": 2, "type": "GOAL_OPERATION_STARTED", "progress": 0.0})
		if tick == 3:
			events.append({"goal_id": 4, "tick": 3, "type": "GOAL_OPERATION_CANCELLED", "progress": 0.1})
		_check(sensing.commit_step(prepared, events, candidate, _context(tick, 3)), "tick %d commits after accepted world" % tick)
		world = candidate
	var before: Dictionary = sensing.snapshot()
	_check(sensing.seal_report_batch(ReportBoundary.new(1, 1, 1, 1, 0, 3, false)), "first window seals")
	_check(sensing.get_system_view() == initial_view, "staged report is not published")
	_check(sensing.update_system_view(ReportBoundary.new(1, 1, 1, 1, 0, 3, false), world), "staged view updates")
	_check(sensing.finish_report_boundary(), "staged report publishes")
	var first: Dictionary = sensing.get_system_view().reports[0]
	var ticks: Array = first.records.map(func(entry: Dictionary) -> int: return entry.data.sense_tick if entry.record_type == "visual" else entry.data.event_tick)
	_check(first.records.size() == 5 and ticks == [0, 0, 2, 2, 2], "N=3 first batch has tick zero, two and target event")
	_check(first.records.any(func(entry: Dictionary) -> bool: return entry.record_type == "goal_operation" and entry.data.type == "GOAL_OPERATION_STARTED"), "goal start entered unified report")
	_check(first.records[0].device_configuration.parameters.enabled == true and first.records.any(func(entry: Dictionary) -> bool: return entry.record_type == "visual" and entry.data.device_id == 1 and entry.data.sense_tick == 2 and entry.device_configuration.parameters.enabled == false), "event-time camera configuration survives change")
	_check(first.records[0].device_configuration.heading == 0.0 and first.records[0].device_configuration.scan_direction == 1 and first.records.any(func(entry: Dictionary) -> bool: return entry.record_type == "visual" and entry.data.device_id == 1 and entry.data.sense_tick == 2 and entry.device_configuration.heading == 0.25 and entry.device_configuration.scan_direction == -1), "event-time heading and direction survive change")
	_check(sensing.get_system_view().world.cameras[0].parameters.enabled == false, "boundary view carries latest public configuration")
	_check(sensing.snapshot().goal_pending.size() == 1 and sensing.snapshot().goal_pending[0].event_tick == 3, "tick three target event remains next period")
	_check(before.goal_pending.size() == 2, "pre-seal snapshot was detached")
	_check(sensing.seal_report_batch(ReportBoundary.new(1, 1, 1, 2, 3, 6, false)), "second window seals")
	_check(sensing.update_system_view(ReportBoundary.new(1, 1, 1, 2, 3, 6, false), world) and sensing.finish_report_boundary(), "second window publishes")
	var second: Dictionary = sensing.get_system_view().reports[1]
	_check(second.records.any(func(entry: Dictionary) -> bool: return entry.record_type == "goal_operation" and entry.data.event_tick == 3), "tick three target event published next")
	var snapshot: Dictionary = sensing.snapshot()
	var bad_snapshot: Dictionary = snapshot.duplicate(true)
	bad_snapshot.goal_pending.append({"actor_id": 0})
	_check(not sensing.restore(bad_snapshot) and sensing.snapshot() == snapshot, "invalid grouped restore cannot contaminate coordinator")
	bad_snapshot = snapshot.duplicate(true)
	bad_snapshot.device_sidecars.append({"record_type": "visual", "data": {}, "device_configuration": {}})
	_check(not sensing.restore(bad_snapshot) and sensing.snapshot() == snapshot, "mismatched configuration sidecar cannot restore")
	_check(sensing.restore(snapshot) and sensing.snapshot() == snapshot, "valid grouped snapshot restores without drift")
	return true

func _coordinator_deployment() -> bool:
	var world: WorldState = _world()
	var sensing := RuntimeSensingCoordinator.new()
	_check(sensing.initialize_round(world, _context(0, 3), 3), "deployment fixture initializes")
	var activations: Array[PlateActivationRecord] = []
	for tick: int in [1, 2, 3]:
		var candidate: WorldState = world.snapshot_copy()
		if tick == 1:
			candidate.registry._put({"id": candidate.next_entity_id, "kind": "pressure_plate", "cell": [1, 1], "parameters": {}, "runtime_state": {"occupants": [], "baseline_ready": false}})
			candidate.next_entity_id += 1
		if tick == 2:
			candidate.player_position = Vector2(160, 96)
		if tick == 3:
			candidate.player_position = Vector2(96, 96)
		_check(candidate.validate().is_empty(), "deployed candidate remains valid at tick %d" % tick)
		var result: SensingStepResult = sensing.prepare_step(SensingKernel.actor_cells(world), candidate, _context(tick, 3))
		_check(result.succeeded(), "deployed candidate senses at tick %d" % tick)
		activations.append_array(result.plate_records)
		_check(sensing.commit_step(result, [], candidate, _context(tick, 3)), "deployed candidate commits at tick %d" % tick)
		world = candidate
	_check(activations.size() == 1 and activations[0].event_tick == 3 and not activations[0].to_data().has("actor_id"), "new plate under player fires only after reentry")
	return true

func _new_robot_and_restart() -> bool:
	var initial: WorldState = _world()
	var sensing := RuntimeSensingCoordinator.new()
	_check(sensing.initialize_round(initial, _context(0, 3), 3), "pre-deployment tick zero initializes")
	var level: Dictionary = PrototypeConfig.level_data()
	level.initial_entities.append({"kind": "robot", "cell": [9, 3], "parameters": {"view_radius": 320.0, "move_speed": 60.0}, "patrol_path": [[9, 3], [10, 3]]})
	var deployed: WorldState = LevelTemplate.from_data(level).instantiate_world()
	_check(deployed != null and deployed.validate().is_empty(), "new robot deployment world valid")
	var candidate: WorldState = deployed.snapshot_copy()
	var prepared: SensingStepResult = sensing.prepare_step(SensingKernel.actor_cells(deployed), candidate, _context(1, 3))
	_check(prepared.succeeded() and prepared.visual_records.any(func(record: ObservationRecord) -> bool: return record.device_id == 7), "new robot samples from deployed world without stale actor list")
	_check(sensing.commit_step(prepared, [], candidate, _context(1, 3)), "new robot observation commits")
	var restarted := RuntimeSensingCoordinator.new()
	_check(restarted.initialize_round(initial, _context(0, 3), 3), "restart initializes fresh tick zero")
	_check(restarted.snapshot().visual_states.size() == 2 and restarted.snapshot().device_buffer.pending.size() == 2, "restart does not retain deployed robot or prior buffer")
	return true

func _simultaneous_plate() -> bool:
	var level: Dictionary = PrototypeConfig.level_data()
	level.initial_entities[1].cell = [1, 1]
	level.initial_entities[1].patrol_path = [[1, 1], [2, 1]]
	level.initial_entities[2].cell = [2, 1]
	var world: WorldState = LevelTemplate.from_data(level).instantiate_world()
	_check(world != null and world.validate().is_empty(), "double-actor fixture is valid")
	var sensing := RuntimeSensingCoordinator.new()
	_check(sensing.initialize_round(world, _context(0, 1), 1), "double-actor coordinator initializes")
	var candidate: WorldState = world.snapshot_copy()
	candidate.player_position = Vector2(160, 96)
	var robot: Dictionary = candidate.registry.get_entity(2)
	robot.runtime_state.position = [160.0, 96.0]
	robot.runtime_state.path_index = 1
	robot.runtime_state.travel_direction = -1
	candidate.registry._put(robot)
	_check(candidate.validate().is_empty(), "double-actor destination is valid")
	var prepared: SensingStepResult = sensing.prepare_step(SensingKernel.actor_cells(world), candidate, _context(1, 1))
	_check(prepared.succeeded() and prepared.plate_records.size() == 2 and prepared.plate_records[0].to_data() == prepared.plate_records[1].to_data(), "same-tick plate records remain two anonymous events")
	_check(sensing.commit_step(prepared, [], candidate, _context(1, 1)), "same-tick double event commits")
	var boundary := ReportBoundary.new(1, 1, 1, 1, 0, 1, false)
	_check(sensing.seal_report_batch(boundary) and sensing.update_system_view(boundary, candidate) and sensing.finish_report_boundary(), "double event seals without sidecar loss")
	boundary = ReportBoundary.new(1, 1, 1, 2, 1, 2, false)
	_check(sensing.seal_report_batch(boundary) and sensing.update_system_view(boundary, candidate) and sensing.finish_report_boundary(), "next half-open window includes tick one events")
	var count: int = 0
	for entry: Dictionary in sensing.get_system_view().reports[1].records:
		if entry.record_type == "plate_activation":
			count += 1
	_check(count == 2, "unified batch retains both anonymous activations")
	return true

func _terminal_half_batch() -> bool:
	var world: WorldState = _world()
	var sensing := RuntimeSensingCoordinator.new()
	var session := GameSession.new(SessionRules.new(3, 100))
	_check(sensing.initialize_round(world, _context(0, 3), 3), "terminal fixture initializes")
	var candidate: WorldState = world.snapshot_copy()
	var prepared: SensingStepResult = sensing.prepare_step(SensingKernel.actor_cells(world), candidate, _context(1, 3))
	_check(prepared.succeeded() and sensing.commit_step(prepared, [], candidate, _context(1, 3)), "terminal tick senses and commits")
	var end_step: PhysicsStepResult = session.advance_physics_step(WorldFrame.new(1, candidate.player_position, true, true))
	_check(end_step.accepted and session.get_state_snapshot().phase == SessionPhase.Phase.ROUND_END and end_step.report_boundary == null, "early success ends without report boundary")
	_check(sensing.get_system_view().reports.is_empty() and sensing.snapshot().device_buffer.pending.size() == 2, "early terminal records stay internal")
	var boundary_world: WorldState = _world()
	var boundary_sensing := RuntimeSensingCoordinator.new()
	var boundary_session := GameSession.new(SessionRules.new(3, 100))
	_check(boundary_sensing.initialize_round(boundary_world, _context(0, 3), 3), "boundary terminal fixture initializes")
	for tick: int in [1, 2, 3]:
		candidate = boundary_world.snapshot_copy()
		prepared = boundary_sensing.prepare_step(SensingKernel.actor_cells(boundary_world), candidate, _context(tick, 3))
		_check(prepared.succeeded() and boundary_sensing.commit_step(prepared, [], candidate, _context(tick, 3)), "boundary terminal tick %d commits" % tick)
		end_step = boundary_session.advance_physics_step(WorldFrame.new(tick, candidate.player_position, tick == 3, tick == 3))
		_check(end_step.accepted, "boundary terminal tick %d advances" % tick)
		boundary_world = candidate
	var boundary: ReportBoundary = end_step.report_boundary
	_check(boundary != null and boundary_sensing.seal_report_batch(boundary) and boundary_sensing.update_system_view(boundary, boundary_world), "boundary terminal stages first window")
	_check(boundary_session.process_report_boundary(func(_b: ReportBoundary) -> void: pass, func(_b: ReportBoundary) -> void: pass) and boundary_sensing.finish_report_boundary(), "boundary terminal publishes first window")
	_check(boundary_session.get_state_snapshot().phase == SessionPhase.Phase.ROUND_END and boundary_sensing.get_system_view().reports.size() == 1 and boundary_sensing.snapshot().device_buffer.pending.is_empty(), "boundary success has one delivered batch and no next-tick event")
	return true

func _make_runtime(world: WorldState, n: int, sensing: RuntimeSensingCoordinator = null, movement_rules: Dictionary = {}, guess_periods: int = 100) -> Dictionary:
	var view: RuntimeWorldView = load("res://scenes/runtime/runtime_test.tscn").instantiate()
	_tree().root.add_child(view)
	view.build_from_world(world)
	var service := WorldCommandService.new(world, {}, SceneWorldSyncAdapter.new(view))
	var session := GameSession.new(SessionRules.new(n, guess_periods))
	var runtime := GameRuntime.new()
	_tree().root.add_child(runtime)
	runtime.auto_advance = false
	runtime.configure(service, session, view, PrototypeConfig.movement_rules() if movement_rules.is_empty() else movement_rules)
	var coordinator: RuntimeSensingCoordinator = sensing if sensing != null else RuntimeSensingCoordinator.new()
	var initialized: bool = coordinator.initialize_round(service.get_world_snapshot(), _context(0, n), n)
	_check(initialized and runtime.configure_sensing(coordinator), "runtime sensing injected")
	return {"runtime": runtime, "view": view, "service": service, "session": session, "sensing": coordinator}

func _real_runtime() -> bool:
	var level: Dictionary = PrototypeConfig.level_data()
	level.player_spawn = [555.0, 352.0]
	var world: WorldState = LevelTemplate.from_data(level).instantiate_world()
	var bundle: Dictionary = _make_runtime(world, 3)
	await _tree().physics_frame
	var runtime: GameRuntime = bundle.runtime
	var first: Dictionary = runtime.step_once(Vector2.ZERO, 1.0 / 60.0, true)
	_check(first.get("ok") == true and runtime.get_last_domain_events().size() == 1, "real goal start accepted at tick one")
	var second: Dictionary = runtime.step_once(Vector2.ZERO, 1.0 / 60.0, false, true)
	_check(second.get("ok") == true and runtime.get_last_domain_events()[0].type == "GOAL_OPERATION_CANCELLED", "real goal cancel accepted at tick two")
	var third: Dictionary = runtime.step_once(Vector2.ZERO, 1.0 / 60.0)
	_check(third.get("ok") == true and bundle.session.get_cycle_snapshot().report_period_id == 1, "real report boundary processed at tick three")
	var reports: Array = bundle.sensing.get_system_view().reports
	_check(reports.size() == 1 and reports[0].records.any(func(entry: Dictionary) -> bool: return entry.record_type == "goal_operation"), "real 3B events joined device report")
	_check(reports[0].records.all(func(entry: Dictionary) -> bool: return (entry.data.sense_tick if entry.record_type == "visual" else entry.data.event_tick) < 3), "real report excludes boundary tick")
	_check(runtime.get_fault().is_empty(), "normal real scene has no report fault")
	await _cleanup(bundle)
	return true

func _real_completion() -> bool:
	var level: Dictionary = PrototypeConfig.level_data()
	level.player_spawn = [555.0, 352.0]
	var rules: Dictionary = PrototypeConfig.movement_rules()
	rules.goal_duration = 0.02
	var bundle: Dictionary = _make_runtime(LevelTemplate.from_data(level).instantiate_world(), 3, null, rules)
	await _tree().physics_frame
	_check(bundle.runtime.step_once(Vector2.ZERO, 1.0 / 60.0, true).get("ok") == true, "short real goal starts")
	_check(bundle.runtime.step_once(Vector2.ZERO, 1.0 / 60.0).get("ok") == true, "short real goal completes")
	_check(bundle.runtime.get_last_domain_events().any(func(event: Dictionary) -> bool: return event.type == "GOAL_OPERATION_COMPLETED"), "3B emits real completed event")
	_check(bundle.runtime.step_once(Vector2.ZERO, 1.0 / 60.0).get("ok") == true, "completed goal report boundary succeeds")
	var types: Array = []
	for entry: Dictionary in bundle.sensing.get_system_view().reports[0].records:
		if entry.record_type == "goal_operation":
			types.append(entry.data.type)
	_check(types == ["GOAL_OPERATION_STARTED", "GOAL_OPERATION_COMPLETED"], "started and completed events join first report")
	await _cleanup(bundle)
	return true

func _plate_reentry() -> bool:
	var level: Dictionary = PrototypeConfig.level_data()
	level.initial_entities[2].cell = [1, 1]
	var bundle: Dictionary = _make_runtime(LevelTemplate.from_data(level).instantiate_world(), 30)
	await _tree().physics_frame
	_check(bundle.runtime.step_once(Vector2.ZERO, 1.0 / 60.0).get("ok") == true, "real plate starts occupied without activation")
	_check(bundle.sensing.snapshot().device_buffer.pending.all(func(entry: Dictionary) -> bool: return entry.record_type != "plate_activation"), "plate under spawn does not fire")
	var left_cell: bool = false
	var returned: bool = false
	for tick: int in 100:
		await _tree().physics_frame
		var direction: Vector2 = Vector2.RIGHT if tick < 43 else Vector2.LEFT
		var result: Dictionary = bundle.runtime.step_once(direction, 1.0 / 60.0)
		if result.get("ok") != true:
			break
		var cell: Vector2i = bundle.service.get_world_snapshot().world_to_cell(bundle.service.get_world_snapshot().player_position)
		left_cell = left_cell or cell != Vector2i(1, 1)
		if left_cell and cell == Vector2i(1, 1):
			returned = true
			break
	var activations: int = 0
	for batch: Dictionary in bundle.sensing.get_system_view().reports:
		for entry: Dictionary in batch.records:
			if entry.record_type == "plate_activation":
				activations += 1
	for entry: Dictionary in bundle.sensing.snapshot().device_buffer.pending:
		if entry.record_type == "plate_activation":
			activations += 1
	_check(left_cell and returned and activations == 1, "real leave and reenter produces one anonymous plate event")
	await _cleanup(bundle)
	return true

func _guess_pause() -> bool:
	var bundle: Dictionary = _make_runtime(_world(), 1, null, {}, 1)
	await _tree().physics_frame
	_check(bundle.runtime.step_once(Vector2.ZERO, 1.0 / 60.0).get("ok") == true, "guess boundary step completes")
	_check(bundle.session.get_state_snapshot().phase == SessionPhase.Phase.GUESS_PAUSED, "guess boundary freezes action")
	var before: Dictionary = bundle.sensing.snapshot()
	_check(bundle.runtime.step_once(Vector2.ZERO, 1.0 / 60.0).get("ok") == false, "paused step is rejected")
	_check(bundle.session.get_cycle_snapshot().simulation_tick == 1 and bundle.sensing.snapshot() == before, "guess pause leaves sensing and report state frozen")
	await _cleanup(bundle)
	return true

func _fault_stops_runtime() -> bool:
	var bundle: Dictionary = _make_runtime(_world(), 3, FailingPrepareCoordinator.new())
	await _tree().physics_frame
	var runtime: GameRuntime = bundle.runtime
	_check(runtime.step_once(Vector2.ZERO, 1.0 / 60.0).get("ok") == false and bundle.session.get_cycle_snapshot().simulation_tick == 0, "prepare failure stops before world and session commit")
	_check(bundle.sensing.get_system_view().reports.is_empty() and not runtime.get_fault().is_empty(), "prepare failure publishes nothing and faults")
	await _cleanup(bundle)
	bundle = _make_runtime(_world(), 3, FailingCommitCoordinator.new())
	await _tree().physics_frame
	runtime = bundle.runtime
	_check(runtime.step_once(Vector2.ZERO, 1.0 / 60.0).get("ok") == false and bundle.session.get_cycle_snapshot().simulation_tick == 1, "commit failure faults after accepted world and session")
	_check(bundle.sensing.get_system_view().reports.is_empty() and not runtime.get_fault().is_empty(), "commit failure publishes no report")
	await _cleanup(bundle)
	bundle = _make_runtime(_world(), 1, FailingSealCoordinator.new())
	await _tree().physics_frame
	runtime = bundle.runtime
	var step: Dictionary = runtime.step_once(Vector2.ZERO, 1.0 / 60.0)
	_check(step.get("ok") == false and not runtime.get_fault().is_empty(), "seal failure faults runtime")
	_check(bundle.sensing.get_system_view().reports.is_empty(), "failed boundary publishes no report")
	var clock: int = bundle.session.get_cycle_snapshot().simulation_tick
	_check(runtime.step_once(Vector2.ZERO, 1.0 / 60.0).get("ok") == false and bundle.session.get_cycle_snapshot().simulation_tick == clock, "fault locks later physics steps")
	await _cleanup(bundle)
	bundle = _make_runtime(_world(), 1, FailingViewCoordinator.new())
	await _tree().physics_frame
	runtime = bundle.runtime
	step = runtime.step_once(Vector2.ZERO, 1.0 / 60.0)
	_check(step.get("ok") == false and not runtime.get_fault().is_empty(), "view update failure faults runtime")
	_check(bundle.sensing.get_system_view().reports.is_empty() and bundle.sensing.snapshot().device_buffer.last_sealed_period_id == 0, "failed view update leaves report unpublished")
	await _cleanup(bundle)
	return true

func _normal_multibatch() -> bool:
	const TARGET_TICKS: int = 600
	var bundle: Dictionary = _make_runtime(_world(), 30)
	await _tree().physics_frame
	var start_usec: int = Time.get_ticks_usec()
	var failures: int = 0
	var process_usec: int = 0
	var max_step_usec: int = 0
	var max_player_distance: float = 0.0
	var max_robot_distance: float = 0.0
	for tick: int in TARGET_TICKS:
		await _tree().physics_frame
		var before: WorldState = bundle.service.get_world_snapshot()
		var input_vector: Vector2 = Vector2.RIGHT if tick % 60 < 30 else Vector2.LEFT
		var step_start: int = Time.get_ticks_usec()
		if bundle.runtime.step_once(input_vector, 1.0 / 60.0).get("ok") != true:
			failures += 1
			break
		var cost: int = Time.get_ticks_usec() - step_start
		process_usec += cost
		max_step_usec = maxi(max_step_usec, cost)
		max_player_distance = maxf(max_player_distance, before.player_position.distance_to(bundle.service.get_world_snapshot().player_position))
		max_robot_distance = maxf(max_robot_distance, DeviceRegistry.vector(before.registry.get_entity(2).runtime_state.position).distance_to(DeviceRegistry.vector(bundle.service.get_world_snapshot().registry.get_entity(2).runtime_state.position)))
	var elapsed_usec: int = Time.get_ticks_usec() - start_usec
	var reports: Array = bundle.sensing.get_system_view().reports
	var record_count: int = 0
	for batch: Dictionary in reports:
		record_count += batch.records.size()
	print("SensingNormalRun: ticks=%d batches=%d records=%d faults=%d wall_ms=%d step_avg_us=%d step_max_us=%d player_max_px=%.2f robot_max_px=%.2f" % [bundle.session.get_cycle_snapshot().simulation_tick, reports.size(), record_count, failures, elapsed_usec / 1000, process_usec / TARGET_TICKS, max_step_usec, max_player_distance, max_robot_distance])
	_check(failures == 0 and bundle.runtime.get_fault().is_empty() and reports.size() == TARGET_TICKS / 30, "normal multibatch run has no report faults")
	_check(record_count < TARGET_TICKS * 2, "same-cell exposure avoids per-tick duplicate visual records")
	_check(max_player_distance < _world().cell_size, "normal player displacement remains below one cell per tick")
	_check(max_robot_distance < _world().cell_size, "normal robot displacement remains below one cell per tick")
	await _cleanup(bundle)
	return true

func _random_multibatch() -> bool:
	const TARGET_TICKS: int = 300
	var bundle: Dictionary = _make_runtime(_world(), 30)
	await _tree().physics_frame
	var rng := RandomNumberGenerator.new()
	rng.seed = 2042
	var directions: Array[Vector2] = [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]
	var input_vector: Vector2 = Vector2.ZERO
	var failures: int = 0
	var start_usec: int = Time.get_ticks_usec()
	for tick: int in TARGET_TICKS:
		await _tree().physics_frame
		if tick % 15 == 0:
			input_vector = directions[rng.randi_range(0, 3)]
		if bundle.runtime.step_once(input_vector, 1.0 / 60.0).get("ok") != true:
			failures += 1
			break
	var reports: Array = bundle.sensing.get_system_view().reports
	var record_count: int = 0
	for batch: Dictionary in reports:
		record_count += batch.records.size()
	print("SensingSeededRun: seed=2042 ticks=%d batches=%d records=%d faults=%d wall_ms=%d" % [bundle.session.get_cycle_snapshot().simulation_tick, reports.size(), record_count, failures, (Time.get_ticks_usec() - start_usec) / 1000])
	_check(failures == 0 and bundle.runtime.get_fault().is_empty() and reports.size() == TARGET_TICKS / 30, "seeded multibatch route has no report faults")
	await _cleanup(bundle)
	return true

func _cleanup(bundle: Dictionary) -> void:
	bundle.runtime.queue_free()
	bundle.view.queue_free()
	await _tree().process_frame

func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree
