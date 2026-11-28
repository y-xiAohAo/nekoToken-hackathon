extends RefCounted
class_name Module6ResetTests
## Session boundary checks; scene and report integration is added below this seam.

var passed: int = 0
var failed: int = 0


class FailingPrepare extends SceneWorldSyncAdapter:
	func prepare(_previous: Dictionary, _candidate: Dictionary, _changes: Dictionary) -> Dictionary:
		return {"ok": false, "errors": [{"code": "INJECTED_PREPARE"}]}


class FailingActivate extends SceneWorldSyncAdapter:
	func activate(prepared: Dictionary) -> bool:
		_discard(prepared)
		return false


func run() -> Dictionary:
	_check(_restore_candidate_is_not_live(), "cycle restore is prepared without mutating live session")
	_check(_decline_ends_round_once(), "declining a hit ends the round without retry")
	_check(await _local_reset_roundtrip(), "local RESET restores the world and archives only delivered reports")
	_check(await _two_resets_from_nonzero_checkpoint(), "two local RESETs can share one nonzero cycle checkpoint")
	_check(await _restore_prepare_failure(), "failed restore preparation preserves the world and reset budget")
	_check(await _restore_activate_failure(), "activation failure locks runtime without charging reset budget")
	return {"passed": passed, "failed": failed}


func _check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		push_error("MODULE 6 RESET TEST FAILED: " + label)


func _restore_candidate_is_not_live() -> bool:
	var session := GameSession.new(SessionRules.new(1, 1))
	var saved_state: Dictionary = session.get_state_snapshot()
	var saved_cycle: Dictionary = session.get_cycle_snapshot()
	session._state.phase = SessionPhase.Phase.RESET_CHOICE
	session._state.frozen_guess_frame = WorldFrame.new(1, Vector2(96, 96), false, false)
	session._cycle.clock.tick = 1
	var before: Dictionary = session.get_state_snapshot()
	var prepared: Dictionary = session.prepare_cycle_restore(saved_state, saved_cycle, 2)
	if prepared.is_empty() or session.get_state_snapshot() != before:
		return false
	session.accept_cycle_restore(prepared)
	var after: Dictionary = session.get_state_snapshot()
	return after.phase == SessionPhase.Phase.ACTION and after.branch_id == 2 \
		and after.active_request_context.is_empty() and after.frozen_guess_frame.is_empty() \
		and session.get_cycle_snapshot().simulation_tick == 0


func _decline_ends_round_once() -> bool:
	var session := GameSession.new(SessionRules.new(1, 1))
	session._state.phase = SessionPhase.Phase.RESET_CHOICE
	return session.decline_local_reset() and session.get_state_snapshot().phase == SessionPhase.Phase.ROUND_END \
		and session.get_state_snapshot().round_result == SessionPhase.RoundResult.FAILURE \
		and not session.decline_local_reset()


func _fixture(adapter_kind: String = "") -> Dictionary:
	var world: WorldState = LevelTemplate.from_data(PrototypeConfig.level_data()).instantiate_world()
	var view := RuntimeWorldView.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(view)
	if world == null or not view.build_from_world(world):
		view.queue_free()
		return {}
	var adapter: SceneWorldSyncAdapter = SceneWorldSyncAdapter.new(view)
	if adapter_kind == "prepare":
		adapter = FailingPrepare.new(view)
	elif adapter_kind == "activate":
		adapter = FailingActivate.new(view)
	var service := WorldCommandService.new(world, PrototypeConfig.combined_policy(), adapter)
	var session := GameSession.new(SessionRules.new(1, 1))
	var sensing := RuntimeSensingCoordinator.new()
	var context: Dictionary = {"round_id": 1, "branch_id": 1, "guess_cycle_id": 1, "report_cycle_id": 1, "sense_tick": 0}
	if not sensing.initialize_round(world, context, 1, PrototypeConfig.system_dispatch_policy()):
		view.queue_free()
		return {}
	var runtime := GameRuntime.new()
	view.add_child(runtime)
	runtime.auto_advance = false
	runtime.configure(service, session, view, PrototypeConfig.movement_rules())
	if not runtime.configure_sensing(sensing) or not runtime.configure_agent(SimulatedAgentGateway.new(), SystemAgentHistory.new(), _agent_rules()):
		view.queue_free()
		return {}
	var history: SystemAgentHistory = runtime._history
	var reset := ResetCoordinator.new(service, session, sensing, RunState.new(world), history)
	if not runtime.configure_reset(reset) or not runtime.capture_initial_checkpoint():
		view.queue_free()
		return {}
	return {"world": world, "view": view, "service": service, "session": session,
		"sensing": sensing, "runtime": runtime, "gateway": runtime._gateway,
		"history": history, "reset": reset}


func _agent_rules() -> Dictionary:
	var rules: Dictionary = PrototypeConfig.system_agent_rules()
	rules["dispatch_policy"] = PrototypeConfig.system_dispatch_policy()
	return rules


func _drive_hit(f: Dictionary) -> Dictionary:
	f.runtime.step_once(Vector2.RIGHT, 1.0 / 60.0)
	var context: Dictionary = f.session.get_state_snapshot().active_request_context
	f.runtime.pump_agent()
	f.gateway.complete_pending({"kind": "response", "raw": {"context": context, "status": "ok",
		"payload": {"shape": "rectangle", "origin_cell": [1, 1], "size": [2, 2]}}})
	return context


func _dirty_live_world(f: Dictionary) -> void:
	f.service._world.obstacle_instances[0].anchor_cell = [8, 2]
	for entity: Dictionary in f.service._world.registry.to_snapshot():
		match entity.kind:
			"camera":
				entity.parameters.scan_center = 0.4
			"goal":
				entity.runtime_state.active = false
				entity.runtime_state.progress = 1.0
				entity.runtime_state.complete = true
			"contact":
				entity.runtime_state.used = true
			_:
				continue
		f.service._world.registry._put(entity)


func _local_reset_roundtrip() -> bool:
	var f: Dictionary = _fixture()
	if f.is_empty():
		return false
	await (Engine.get_main_loop() as SceneTree).physics_frame
	var old_context: Dictionary = _drive_hit(f)
	if f.session.get_state_snapshot().phase != SessionPhase.Phase.RESET_CHOICE:
		f.view.queue_free()
		return false
	var start: Vector2 = DeviceRegistry.vector(f.reset.get_checkpoint_snapshot().world.player_position)
	_dirty_live_world(f)
	var chosen: bool = f.runtime.choose_local_reset()
	var restored: bool = chosen and f.session.get_state_snapshot().phase == SessionPhase.Phase.ACTION \
		and f.session.get_state_snapshot().branch_id == 2 and f.session.get_cycle_snapshot().simulation_tick == 0 \
		and f.service.get_world_snapshot().to_snapshot() == f.reset.get_checkpoint_snapshot().world \
		and f.view.get_player().global_position.is_equal_approx(start) \
		and f.reset.get_run_snapshot().remaining_local_resets == 2 \
		and f.runtime._sensing.get_system_view().reports.is_empty() \
		and f.history.snapshot().entries.size() == 2 \
		and f.history.snapshot().entries[1].kind == "archived_report"
	f.runtime.step_once(Vector2.ZERO, 1.0 / 60.0)
	var view: Dictionary = f.runtime._sensing.get_system_view()
	restored = restored and view.reports.size() == 1 and view.reports[0].branch_id == 2 \
		and not view.reports[0].records.is_empty() and view.reports[0].records[0].origin_branch_id == 1
	f.runtime.on_agent_result(old_context, "location_guess", {"kind": "response", "raw": null})
	restored = restored and f.runtime.get_fault().is_empty() and not f.runtime.choose_local_reset() \
		and f.reset.get_run_snapshot().remaining_local_resets == 2
	f.view.queue_free()
	return restored


func _two_resets_from_nonzero_checkpoint() -> bool:
	var f: Dictionary = _fixture()
	if f.is_empty():
		return false
	await (Engine.get_main_loop() as SceneTree).physics_frame
	f.runtime.step_once(Vector2.ZERO, 1.0 / 60.0)
	var guess: Dictionary = f.session.get_state_snapshot().active_request_context
	f.runtime.pump_agent()
	f.gateway.complete_pending({"kind": "response", "raw": {"context": guess, "status": "ok",
		"payload": {"shape": "rectangle", "origin_cell": [10, 1], "size": [1, 1]}}})
	var dispatch: Dictionary = f.session.get_state_snapshot().active_request_context
	f.runtime.pump_agent()
	f.gateway.complete_pending({"kind": "response", "raw": {"context": dispatch, "status": "ok",
		"payload": {"mode": "KEEP_CURRENT", "commands": []}}})
	if not f.runtime.complete_cycle_start() or f.session.get_cycle_snapshot().simulation_tick != 1:
		f.view.queue_free()
		return false
	_drive_hit(f)
	var first: bool = f.runtime.choose_local_reset()
	_drive_hit(f)
	var second: bool = f.runtime.choose_local_reset()
	var state: Dictionary = f.session.get_state_snapshot()
	var view: Dictionary = f.runtime._sensing.get_system_view()
	var result: bool = first and second and state.phase == SessionPhase.Phase.ACTION and state.branch_id == 3 \
		and f.session.get_cycle_snapshot().simulation_tick == 1 and f.reset.get_run_snapshot().remaining_local_resets == 1 \
		and view.reports.size() == 1 and view.reports[0].branch_id == 1 and f.runtime.get_fault().is_empty()
	f.runtime.step_once(Vector2.ZERO, 1.0 / 60.0)
	result = result and f.runtime._sensing.get_system_view().reports.size() == 2 \
		and f.runtime._sensing.get_system_view().reports[-1].branch_id == 3
	f.view.queue_free()
	return result


func _restore_prepare_failure() -> bool:
	var f: Dictionary = _fixture("prepare")
	if f.is_empty():
		return false
	await (Engine.get_main_loop() as SceneTree).physics_frame
	_drive_hit(f)
	var before: Dictionary = f.service.get_world_snapshot().to_snapshot()
	var failed: bool = not f.runtime.choose_local_reset()
	var result: bool = failed and f.service.get_world_snapshot().to_snapshot() == before \
		and f.reset.get_run_snapshot().remaining_local_resets == 3 \
		and f.session.get_state_snapshot().phase == SessionPhase.Phase.RESET_CHOICE \
		and f.runtime.get_fault().is_empty() and f.reset.get_last_error() == "SYNC_PREPARE_FAILED"
	f.view.queue_free()
	return result


func _restore_activate_failure() -> bool:
	var f: Dictionary = _fixture("activate")
	if f.is_empty():
		return false
	await (Engine.get_main_loop() as SceneTree).physics_frame
	_drive_hit(f)
	var before: Dictionary = f.service.get_world_snapshot().to_snapshot()
	var failed: bool = not f.runtime.choose_local_reset()
	var result: bool = failed and f.service.get_world_snapshot().to_snapshot() == before \
		and f.reset.get_run_snapshot().remaining_local_resets == 3 \
		and f.session.get_state_snapshot().phase == SessionPhase.Phase.RESET_CHOICE \
		and not f.runtime.get_fault().is_empty()
	f.view.queue_free()
	return result
