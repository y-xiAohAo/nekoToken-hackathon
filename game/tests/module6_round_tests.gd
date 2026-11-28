extends Module6ResetTests
class_name Module6RoundTests
## End-to-end round transitions using the real graybox restoration channel.


func run() -> Dictionary:
	passed = 0
	failed = 0
	_check(await _success_starts_clean_round(), "successful round archives history and starts a clean configured round")
	_check(await _failure_starts_next_round(), "final failure can advance to the next round")
	_check(await _second_round_local_reset(), "local RESET works after entering a later round")
	_check(_fourth_round_has_no_fifth(), "fourth settled round does not create a fifth")
	_check(await _invalid_setup_stops_without_world_commit(), "invalid round setup stops without changing the active world")
	return {"passed": passed, "failed": failed}


func _dirty_fixed_entities(f: Dictionary) -> void:
	for entity: Dictionary in f.service._world.registry.to_snapshot():
		if entity.kind == "goal":
			entity.runtime_state.active = false
			entity.runtime_state.progress = 1.0
			entity.runtime_state.complete = true
		elif entity.kind == "contact":
			entity.runtime_state.used = true
		else:
			continue
		f.service._world.registry._put(entity)


func _fixed_entities_reset(world: WorldState) -> bool:
	for entity: Dictionary in world.registry.to_snapshot():
		if entity.kind == "goal" and (entity.runtime_state.active or entity.runtime_state.progress != 0.0 or entity.runtime_state.complete):
			return false
		if entity.kind == "contact" and entity.runtime_state.used:
			return false
	return true


func _success_starts_clean_round() -> bool:
	var f: Dictionary = _fixture()
	if f.is_empty():
		return false
	await (Engine.get_main_loop() as SceneTree).physics_frame
	_drive_hit(f)
	_dirty_fixed_entities(f)
	f.service._world.next_entity_id = 20
	f.service._world.next_obstacle_id = 8
	f.session._finish_round(SessionPhase.RoundResult.SUCCESS)
	var advanced: bool = f.runtime.advance_round()
	var world: WorldState = f.service.get_world_snapshot()
	var state: Dictionary = f.session.get_state_snapshot()
	var run: Dictionary = f.reset.get_run_snapshot()
	var camera: Dictionary = world.registry.get_entity(1)
	var history: Array = f.history.snapshot().entries
	var result: bool = advanced and state.phase == SessionPhase.Phase.ACTION and state.round_id == 2 and state.branch_id == 2 \
		and f.session.get_cycle_snapshot().simulation_tick == 0 and run.remaining_local_resets == 3 \
		and run.next_entity_id == 20 and run.next_obstacle_id == 8 \
		and world.next_entity_id == 20 and world.next_obstacle_id == 8 \
		and run.round_results == [{"round_id": 1, "result": SessionPhase.RoundResult.SUCCESS}] \
		and _fixed_entities_reset(world) and not is_equal_approx(camera.parameters.scan_center, 0.0) \
		and f.runtime._sensing.get_system_view().reports.is_empty() \
		and history.any(func(entry: Dictionary) -> bool: return entry.kind == "archived_report" and entry.reason == "previous_round") \
		and history[-1].kind == "round_setup" and history[-1].status == "APPLIED" \
		and not f.reset.get_checkpoint_snapshot().is_empty() and f.runtime.get_fault().is_empty()
	f.view.queue_free()
	return result


func _failure_starts_next_round() -> bool:
	var f: Dictionary = _fixture()
	if f.is_empty():
		return false
	await (Engine.get_main_loop() as SceneTree).physics_frame
	_drive_hit(f)
	var declined: bool = f.runtime.decline_local_reset()
	var advanced: bool = f.runtime.advance_round()
	var result: bool = declined and advanced and f.reset.get_run_snapshot().round_results[0].result == SessionPhase.RoundResult.FAILURE \
		and f.session.get_state_snapshot().round_id == 2 and f.session.get_state_snapshot().phase == SessionPhase.Phase.ACTION
	f.view.queue_free()
	return result


func _second_round_local_reset() -> bool:
	var f: Dictionary = _fixture()
	if f.is_empty():
		return false
	await (Engine.get_main_loop() as SceneTree).physics_frame
	_drive_hit(f)
	f.session._finish_round(SessionPhase.RoundResult.SUCCESS)
	if not f.runtime.advance_round():
		f.view.queue_free()
		return false
	_drive_hit(f)
	var chosen: bool = f.runtime.choose_local_reset()
	var result: bool = chosen and f.session.get_state_snapshot().phase == SessionPhase.Phase.ACTION \
		and f.session.get_state_snapshot().round_id == 2 and f.session.get_state_snapshot().branch_id == 3 \
		and f.reset.get_run_snapshot().remaining_local_resets == 2 and f.runtime.get_fault().is_empty()
	f.view.queue_free()
	return result


func _fourth_round_has_no_fifth() -> bool:
	var world: WorldState = LevelTemplate.from_data(PrototypeConfig.level_data()).instantiate_world()
	var sensing := RuntimeSensingCoordinator.new()
	var context: Dictionary = {"round_id": 4, "branch_id": 9, "guess_cycle_id": 1, "report_cycle_id": 1, "sense_tick": 0}
	if not sensing.initialize_round(world, context, 30):
		return false
	var session := GameSession.new(SessionRules.new(30, 2))
	session._state.round_id = 4
	session._state.branch_id = 9
	session._state.phase = SessionPhase.Phase.ROUND_END
	session._state.round_result = SessionPhase.RoundResult.FAILURE
	var run := RunState.new(world)
	run._round_id = 4
	run._branch_id = 9
	var reset := ResetCoordinator.new(WorldCommandService.new(world, {}, WorldSyncAdapter.new()), session, sensing, run, SystemAgentHistory.new())
	var advanced: bool = reset.advance_round()
	var snapshot: Dictionary = reset.get_run_snapshot()
	return advanced and session.get_state_snapshot().phase == SessionPhase.Phase.ROUND_END and session.get_state_snapshot().round_id == 4 \
		and snapshot.round_results.size() == 1 and snapshot.round_id == 4 and snapshot.next_branch_id == 2 \
		and not reset.advance_round()


func _invalid_setup_stops_without_world_commit() -> bool:
	var f: Dictionary = _fixture()
	if f.is_empty():
		return false
	await (Engine.get_main_loop() as SceneTree).physics_frame
	_drive_hit(f)
	f.session._finish_round(SessionPhase.RoundResult.SUCCESS)
	f.reset._round_fixture = {"scan_center_candidates": [99.0]}
	var before: Dictionary = f.service.get_world_snapshot().to_snapshot()
	var advanced: bool = f.runtime.advance_round()
	var result: bool = not advanced and f.service.get_world_snapshot().to_snapshot() == before \
		and f.session.get_state_snapshot().phase == SessionPhase.Phase.ROUND_SETUP_PAUSED \
		and f.reset.get_run_snapshot().round_results.is_empty() and not f.runtime.get_fault().is_empty()
	f.view.queue_free()
	return result
