extends RefCounted
class_name Module7BDualAgentTests

var passed: int = 0
var failed: int = 0


func run() -> Dictionary:
	await _assistant_then_system()
	await _system_then_assistant()
	return {"passed": passed, "failed": failed}


func _fixture() -> Dictionary:
	var level: Dictionary = PrototypeConfig.level_data()
	level.player_spawn = [96.0, 300.0]
	var world: WorldState = LevelTemplate.from_data(level).instantiate_world()
	var view := RuntimeWorldView.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(view)
	if world == null or not view.build_from_world(world):
		view.queue_free()
		return {}
	var service := WorldCommandService.new(world, PrototypeConfig.combined_policy(), SceneWorldSyncAdapter.new(view))
	var session := GameSession.new(SessionRules.new(2, 1))
	var contact := ContactSessionController.new(session, service, view,
		SimulatedPlayerAssistant.new(PrototypeConfig.simulated_assistant_scan(), PrototypeConfig.simulated_assistant_route()),
		PrototypeConfig.player_assistant_route_rules())
	var runtime := GameRuntime.new()
	view.add_child(runtime)
	runtime.auto_advance = false
	runtime.configure(service, session, view, PrototypeConfig.movement_rules())
	var sensing := RuntimeSensingCoordinator.new()
	var context: Dictionary = {"round_id": 1, "branch_id": 1, "guess_cycle_id": 1, "report_cycle_id": 1, "sense_tick": 0}
	if not sensing.initialize_round(world, context, 2, PrototypeConfig.system_dispatch_policy()) \
			or not runtime.configure_sensing(sensing) or not runtime.configure_contact(contact):
		view.queue_free()
		return {}
	var gateway := SimulatedAgentGateway.new()
	var history := SystemAgentHistory.new()
	var rules: Dictionary = PrototypeConfig.system_agent_rules()
	rules["dispatch_policy"] = PrototypeConfig.system_dispatch_policy()
	if not runtime.configure_agent(gateway, history, rules):
		view.queue_free()
		return {}
	var reset := ResetCoordinator.new(service, session, sensing, RunState.new(world), history, contact)
	if not runtime.configure_reset(reset) or not runtime.capture_initial_checkpoint():
		view.queue_free()
		return {}
	var robot_id: int = 0
	for entity: Dictionary in world.registry.to_snapshot():
		if entity.kind == "robot":
			robot_id = entity.id
	return {"view": view, "service": service, "session": session, "sensing": sensing, "runtime": runtime,
		"gateway": gateway, "history": history, "contact": contact, "reset": reset, "robot_id": robot_id}


func _assistant_then_system() -> void:
	var f: Dictionary = _fixture()
	_check(not f.is_empty(), "assistant-system fixture")
	if f.is_empty(): return
	var assistant_cells: Array = await _apply_assistant_route(f)
	_check(assistant_cells == [[5, 3], [6, 3], [6, 2]], "assistant applies first route")
	_check(_drive_system_dispatch(f, [[5, 3], [5, 2]]), "system dispatch follows assistant")
	var robot: Dictionary = f.service.get_world_snapshot().registry.get_entity(f.robot_id)
	_check(robot.patrol_path == [[5, 3], [5, 2]] and f.service.get_world_snapshot().world_revision == 2, "later system route overwrites same control item")
	_check(f.runtime.get_fault().is_empty() and f.history.snapshot().entries.size() == 2, "assistant-system order has no fault and keeps system history")
	f.view.queue_free()
	await (Engine.get_main_loop() as SceneTree).process_frame


func _system_then_assistant() -> void:
	var f: Dictionary = _fixture()
	_check(not f.is_empty(), "system-assistant fixture")
	if f.is_empty(): return
	_check(_drive_system_dispatch(f, [[5, 3], [5, 2]]), "system applies first route")
	_check(f.runtime.complete_cycle_start() and f.session.get_state_snapshot().phase == SessionPhase.Phase.ACTION, "real checkpoint resumes post-dispatch cycle")
	var assistant_cells: Array = await _apply_assistant_route(f)
	_check(assistant_cells == [[5, 3], [6, 3], [6, 2]], "assistant proposes from current trusted anchor")
	var robot: Dictionary = f.service.get_world_snapshot().registry.get_entity(f.robot_id)
	_check(robot.patrol_path == assistant_cells and f.service.get_world_snapshot().world_revision == 2, "later assistant route overwrites same control item")
	_check(f.runtime.get_fault().is_empty() and f.history.snapshot().entries.size() == 2, "system-assistant order has no concurrent agent fault")
	f.view.queue_free()
	await (Engine.get_main_loop() as SceneTree).process_frame


func _apply_assistant_route(f: Dictionary) -> Array:
	await (Engine.get_main_loop() as SceneTree).physics_frame
	if f.runtime.step_once(Vector2.ZERO, 1.0 / 60.0, true).get("ok") != true \
			or f.session.get_state_snapshot().phase != SessionPhase.Phase.CONTACT_PAUSED:
		_check(false, "assistant enters contact in legal phase")
		return []
	var rejected_pump: Dictionary = f.runtime.pump_agent()
	_check(rejected_pump.get("ok") != true and rejected_pump.errors[0].code == "INVALID_PHASE" and f.runtime.get_fault().is_empty(), "system cannot execute during contact")
	var robot: RobotController = f.view.get_entity_node(f.robot_id)
	if not f.runtime.select_contact_target_at(robot.get_global_transform_with_canvas() * Vector2.ZERO) \
			or not f.runtime.submit_contact_text("调整路线"):
		_check(false, "assistant route proposal in integrated runtime")
		return []
	var proposal: Dictionary = f.runtime.get_contact_ui_snapshot().proposal
	if not f.runtime.confirm_contact_proposal(proposal.token):
		_check(false, "assistant route commit in integrated runtime")
		return []
	return proposal.preview_cells


func _drive_system_dispatch(f: Dictionary, cells: Array) -> bool:
	for _i: int in 4:
		if f.session.get_state_snapshot().phase == SessionPhase.Phase.ACTION:
			f.runtime.step_once(Vector2.ZERO, 1.0 / 60.0)
	if f.session.get_state_snapshot().phase != SessionPhase.Phase.GUESS_PAUSED:
		return false
	var guess_context: Dictionary = f.session.get_state_snapshot().active_request_context
	if f.runtime.pump_agent().get("ok") != true:
		return false
	f.gateway.complete_pending({"kind": "response", "raw": {"context": guess_context, "status": "ok",
		"payload": {"shape": "rectangle", "origin_cell": [10, 1], "size": [1, 1]}}})
	if f.session.get_state_snapshot().phase != SessionPhase.Phase.DISPATCH_PAUSED:
		return false
	if f.runtime.submit_contact_text("不应进入联络"):
		return false
	var dispatch_context: Dictionary = f.session.get_state_snapshot().active_request_context
	if f.runtime.pump_agent().get("ok") != true:
		return false
	f.gateway.complete_pending({"kind": "response", "raw": {"context": dispatch_context, "status": "ok", "payload": {
		"mode": "APPLY", "commands": [{"type": "SetPatrolPath", "robot_id": f.robot_id, "cells": cells.duplicate(true)}]}}})
	return f.session.get_state_snapshot().phase == SessionPhase.Phase.CYCLE_START_PENDING and f.runtime.get_fault().is_empty()


func _check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		push_error("MODULE 7B DUAL AGENT TEST FAILED: " + label)
