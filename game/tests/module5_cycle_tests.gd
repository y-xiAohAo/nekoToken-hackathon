extends RefCounted
class_name Module5CycleTests
## Module 5 protocol and one-cycle contracts; all values are prototype fixtures.

var passed: int = 0
var failed: int = 0

class FailingSeal extends RuntimeSensingCoordinator:
	func seal_report_batch(_boundary: ReportBoundary) -> bool:
		return false

class FailingActivate extends SceneWorldSyncAdapter:
	func activate(prepared: Dictionary) -> bool:
		_discard(prepared)
		return false


func run() -> Dictionary:
	_check(_location_protocol(), "strict location DTO and rectangle")
	_check(_dispatch_protocol(), "strict dispatch DTO and known command")
	_check(_session_rejection(), "first dispatch rejection renews request without advancing cycle")
	_check(_history_gateway(), "history and deferred gateway preserve request identity")
	_check(await _runtime_roundtrip(), "published report drives one miss and real obstacle dispatch")
	_check(await _runtime_retry_exhaustion(), "two safe dispatch rejections exhaust into STOP")
	_check(await _runtime_hit(), "hit is program computed and stops before dispatch")
	_check(_session_success_miss(), "frozen success with miss ends round without dispatch")
	_check(await _runtime_protocol_faults(), "wrong identity, timeout, disconnect and empty reply stop with late callbacks ignored")
	_check(await _report_fault_zero_agent_calls(), "report fault prevents every agent call")
	_check(await _activate_fault_is_stop(), "SceneSync activation fault stops without retry receipt")
	_check(await _runtime_retry_success(), "first rejected dispatch can be corrected on new request")
	return {"passed": passed, "failed": failed}


func _check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		push_error("MODULE 5 CYCLE TEST FAILED: " + label)


func _context(request_id: int = 1) -> Dictionary:
	return AgentProtocol.make_request_context(AgentProtocol.SYSTEM_AGENT, request_id, 1, 1, 1)


func _view() -> Dictionary:
	var world: WorldState = LevelTemplate.from_data(PrototypeConfig.level_data()).instantiate_world()
	var view := SystemAgentView.new()
	if world == null or not view.initialize(world, PrototypeConfig.system_dispatch_policy()):
		return {}
	return view.to_data()


func _location_protocol() -> bool:
	var context: Dictionary = _context()
	var constraints: Dictionary = PrototypeConfig.location_constraints()
	var request: Dictionary = AgentProtocol.make_location_request(context, _view(), {"simulation_tick": 60, "report_period_id": 2}, constraints)
	var wire: String = AgentProtocol.serialize_request(request)
	var injected_request: Dictionary = request.duplicate(true)
	injected_request["hit"] = true
	var response: Dictionary = {"context": context, "status": "ok", "payload": {"shape": "rectangle", "origin_cell": [2, 2], "size": [2, 2]}}
	var parsed: Dictionary = AgentProtocol.parse_location_response(response, context, constraints, Vector2i(12, 8))
	var wrong: Dictionary = response.duplicate(true)
	wrong.payload["hit"] = false
	var outside: Dictionary = response.duplicate(true)
	outside.payload.origin_cell = [11, 7]
	for field: String in ["request_id", "round_id", "branch_id", "guess_cycle_id"]:
		var mismatch: Dictionary = response.duplicate(true)
		mismatch.context[field] += 1
		if AgentProtocol.parse_location_response(mismatch, context, constraints, Vector2i(12, 8)).get("ok") == true:
			return false
	for invalid: Dictionary in [
		{"shape": "circle", "origin_cell": [2, 2], "size": [1, 1]},
		{"shape": "rectangle", "origin_cell": [2, 2], "size": [0, 1]},
		{"shape": "rectangle", "origin_cell": [2, 2], "size": [3, 1]},
		{"shape": "rectangle", "origin_cell": [2.0, 2], "size": [1, 1]},
	]:
		var malformed: Dictionary = response.duplicate(true)
		malformed.payload = invalid
		if AgentProtocol.parse_location_response(malformed, context, constraints, Vector2i(12, 8)).get("ok") == true:
			return false
	var self_reported: Dictionary = response.duplicate(true)
	self_reported["success"] = true
	return DeviceRegistry.fields(request, ["context", "request_type", "view", "as_of", "constraints"]) \
		and not wire.is_empty() and AgentProtocol.serialize_request(injected_request).is_empty() \
		and request.request_type == "location_guess" and DeviceRegistry.fields(request.view, ["world", "reports", "history"]) \
		and parsed.get("ok") == true and AgentProtocol.parse_location_response(wrong, context, constraints, Vector2i(12, 8)).get("ok") == false \
		and AgentProtocol.parse_location_response(outside, context, constraints, Vector2i(12, 8)).get("ok") == false \
		and AgentProtocol.parse_location_response(self_reported, context, constraints, Vector2i(12, 8)).get("ok") == false


func _dispatch_protocol() -> bool:
	var context: Dictionary = _context(2)
	var request: Dictionary = AgentProtocol.make_dispatch_request(context, _view(), {"simulation_tick": 60, "report_period_id": 2}, PrototypeConfig.system_dispatch_policy(), null)
	var response: Dictionary = {"context": context, "status": "ok", "payload": {"mode": "APPLY", "commands": [{"type": "MoveObstacle", "obstacle_id": 1, "anchor_cell": [8, 2]}]}}
	var parsed: Dictionary = AgentProtocol.parse_dispatch_response(response, context)
	var unknown: Dictionary = response.duplicate(true)
	unknown.payload.commands[0].type = "Teleport"
	var self_reported: Dictionary = response.duplicate(true)
	self_reported["phase"] = "SUCCESS"
	return DeviceRegistry.fields(request, ["context", "request_type", "view", "as_of", "policy", "previous_rejection"]) \
		and request.request_type == "dispatch" and request.previous_rejection == null \
		and parsed.get("ok") == true and AgentProtocol.parse_dispatch_response(unknown, context).get("ok") == false \
		and AgentProtocol.parse_dispatch_response(self_reported, context).get("ok") == false


func _session_rejection() -> bool:
	var session := GameSession.new(SessionRules.new(1, 1))
	var frame := WorldFrame.new(1, Vector2(96, 96), false, false)
	if not session.advance_physics_step(frame).accepted or not session.process_report_boundary(func(_b: ReportBoundary) -> void: pass, func(_b: ReportBoundary) -> void: pass):
		return false
	var state: Dictionary = session.get_state_snapshot()
	if state.phase != SessionPhase.Phase.GUESS_PAUSED or not state.frozen_guess_frame.has("world_revision") or state.get("active_request_type") != "location_guess":
		return false
	var guess: Dictionary = state.active_request_context
	if not session.accept_guess_result(guess, false):
		return false
	state = session.get_state_snapshot()
	if state.phase != SessionPhase.Phase.DISPATCH_PAUSED or state.get("active_request_type") != "dispatch":
		return false
	var original: Dictionary = state.active_request_context
	var receipt: Dictionary = {"status": "REJECTED", "context": original.duplicate(true),
		"errors": [{"code": "PLACEMENT_REJECTED", "command_index": 0}]}
	var decision: Dictionary = session.note_dispatch_rejection(original, receipt, 2)
	state = session.get_state_snapshot()
	return decision.get("retry") == true and state.phase == SessionPhase.Phase.DISPATCH_PAUSED \
		and state.guess_cycle_id == 1 and state.get("dispatch_attempts") == 1 \
		and state.active_request_context.request_id != original.request_id and state.get("last_dispatch_rejection") == receipt


func _history_gateway() -> bool:
	var context: Dictionary = _context(7)
	var history := SystemAgentHistory.new()
	var entry: Dictionary = {"kind": "guess", "context": context, "as_of": {"simulation_tick": 60, "report_period_id": 2},
		"origin_cell": [2, 2], "size": [1, 1], "verdict": "MISS"}
	if not history.append_guess(entry):
		return false
	entry.origin_cell = [99, 99]
	if history.snapshot().get("entries", []).size() != 1 or history.snapshot().entries[0].origin_cell != [2, 2]:
		return false
	var request: Dictionary = AgentProtocol.make_location_request(context, _view(), {"simulation_tick": 60, "report_period_id": 2}, PrototypeConfig.location_constraints())
	var raw: Variant = SimulatedSystemAgent.respond(request, {"location": {"shape": "rectangle", "origin_cell": [2, 2], "size": [1, 1]}})
	if not raw is Dictionary or raw.get("context") != context:
		return false
	var returned: Array = []
	var gateway := SimulatedAgentGateway.new()
	if not gateway.submit(request, func(result: Variant) -> void: returned.append(result)) or gateway.call_count != 1:
		return false
	return gateway.complete_pending({"kind": "response", "raw": raw}) and returned.size() == 1 and returned[0].raw.context == context


func _runtime_fixture(fail_seal: bool = false, fail_activate: bool = false) -> Dictionary:
	var world: WorldState = LevelTemplate.from_data(PrototypeConfig.level_data()).instantiate_world()
	if world == null:
		return {}
	var view := RuntimeWorldView.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(view)
	if not view.build_from_world(world):
		view.queue_free()
		return {}
	var adapter: SceneWorldSyncAdapter = FailingActivate.new(view) if fail_activate else SceneWorldSyncAdapter.new(view)
	var service := WorldCommandService.new(world, PrototypeConfig.combined_policy(), adapter)
	var session := GameSession.new(SessionRules.new(1, 1))
	var sensing: RuntimeSensingCoordinator = FailingSeal.new() if fail_seal else RuntimeSensingCoordinator.new()
	var context: Dictionary = {"round_id": 1, "branch_id": 1, "guess_cycle_id": 1, "report_cycle_id": 1, "sense_tick": 0}
	if not sensing.initialize_round(world, context, 1, PrototypeConfig.system_dispatch_policy()):
		view.queue_free()
		return {}
	var runtime := GameRuntime.new()
	view.add_child(runtime)
	runtime.auto_advance = false
	runtime.configure(service, session, view, PrototypeConfig.movement_rules())
	if not runtime.configure_sensing(sensing):
		view.queue_free()
		return {}
	var gateway := SimulatedAgentGateway.new()
	var history := SystemAgentHistory.new()
	var rules: Dictionary = PrototypeConfig.system_agent_rules()
	rules["dispatch_policy"] = PrototypeConfig.system_dispatch_policy()
	if not runtime.configure_agent(gateway, history, rules):
		view.queue_free()
		return {}
	return {"view": view, "runtime": runtime, "service": service, "session": session,
		"sensing": sensing, "gateway": gateway, "history": history}


func _runtime_roundtrip() -> bool:
	var f: Dictionary = _runtime_fixture()
	if f.is_empty():
		return false
	await (Engine.get_main_loop() as SceneTree).physics_frame
	var before: bool = f.gateway.call_count == 0
	var step: Dictionary = f.runtime.step_once(Vector2.ZERO, 1.0 / 60.0)
	if not before or step.get("ok") != true or f.session.get_state_snapshot().phase != SessionPhase.Phase.GUESS_PAUSED:
		f.view.queue_free()
		return false
	var guess_context: Dictionary = f.session.get_state_snapshot().active_request_context
	var sent: Dictionary = f.runtime.pump_agent()
	var pending_snapshot: Dictionary = f.runtime.get_agent_snapshot()
	pending_snapshot.pending_context.request_id = 999
	var guess: Dictionary = {"context": guess_context, "status": "ok", "payload": {"shape": "rectangle", "origin_cell": [10, 1], "size": [1, 1]}}
	var replied: bool = sent.get("ok") == true and f.gateway.call_count == 1 \
		and f.runtime.get_agent_snapshot().pending_context.request_id == guess_context.request_id \
		and f.gateway.complete_pending({"kind": "response", "raw": guess})
	var missed: bool = f.session.get_state_snapshot().phase == SessionPhase.Phase.DISPATCH_PAUSED
	var dispatch_context: Dictionary = f.session.get_state_snapshot().active_request_context
	var dispatched: Dictionary = f.runtime.pump_agent()
	var command: Dictionary = {"type": "MoveObstacle", "obstacle_id": 1, "anchor_cell": [8, 2]}
	var response: Dictionary = {"context": dispatch_context, "status": "ok", "payload": {"mode": "APPLY", "commands": [command]}}
	var completed: bool = dispatched.get("ok") == true and f.gateway.call_count == 2 and f.gateway.complete_pending({"kind": "response", "raw": response})
	var world: WorldState = f.service.get_world_snapshot()
	var ok: bool = replied and missed and completed and f.runtime.get_fault().is_empty() \
		and f.session.get_state_snapshot().phase == SessionPhase.Phase.CYCLE_START_PENDING \
		and world.world_revision == 1 and world.obstacle_instances[0].anchor_cell == [8, 2] \
		and f.history.snapshot().get("entries", []).size() == 2
	f.view.queue_free()
	return ok


func _runtime_retry_exhaustion() -> bool:
	var f: Dictionary = _runtime_fixture()
	if f.is_empty():
		return false
	await (Engine.get_main_loop() as SceneTree).physics_frame
	if f.runtime.step_once(Vector2.ZERO, 1.0 / 60.0).get("ok") != true:
		f.view.queue_free()
		return false
	var guess_context: Dictionary = f.session.get_state_snapshot().active_request_context
	f.runtime.pump_agent()
	f.gateway.complete_pending({"kind": "response", "raw": {"context": guess_context, "status": "ok", "payload": {"shape": "rectangle", "origin_cell": [10, 1], "size": [1, 1]}}})
	var first_context: Dictionary = f.session.get_state_snapshot().active_request_context
	var before: Dictionary = f.service.get_world_snapshot().to_snapshot()
	f.runtime.pump_agent()
	var forbidden: Dictionary = {"type": "MoveObstacle", "obstacle_id": 1, "anchor_cell": [1, 1]}
	f.gateway.complete_pending({"kind": "response", "raw": {"context": first_context, "status": "ok", "payload": {"mode": "APPLY", "commands": [forbidden]}}})
	var next: Dictionary = f.session.get_state_snapshot()
	var retried: bool = next.phase == SessionPhase.Phase.DISPATCH_PAUSED and next.active_request_context.request_id != first_context.request_id \
		and f.service.get_world_snapshot().to_snapshot() == before and f.runtime.get_fault().is_empty()
	f.runtime.on_agent_result(first_context, "dispatch", {"kind": "response", "raw": {"context": first_context, "status": "ok", "payload": {"mode": "KEEP_CURRENT", "commands": []}}})
	retried = retried and f.runtime.get_fault().is_empty() and f.session.get_state_snapshot().active_request_context == next.active_request_context
	f.runtime.pump_agent()
	var retry_request: Dictionary = f.gateway.get("_pending_request")
	retried = retried and retry_request.get("previous_rejection", {}).get("context", {}).get("request_id") == first_context.request_id \
		and retry_request.previous_rejection.errors[0].code == "PLACEMENT_REJECTED" \
		and not str(retry_request.previous_rejection).contains("player")
	f.gateway.complete_pending({"kind": "response", "raw": {"context": next.active_request_context, "status": "ok", "payload": {"mode": "APPLY", "commands": [forbidden]}}})
	var ok: bool = retried and not f.runtime.get_fault().is_empty() and f.service.get_world_snapshot().to_snapshot() == before \
		and f.history.snapshot().get("entries", []).size() == 3 and f.gateway.call_count == 3
	f.view.queue_free()
	return ok


func _runtime_hit() -> bool:
	var f: Dictionary = _runtime_fixture()
	if f.is_empty():
		return false
	await (Engine.get_main_loop() as SceneTree).physics_frame
	if f.runtime.step_once(Vector2.ZERO, 1.0 / 60.0).get("ok") != true:
		f.view.queue_free()
		return false
	var context: Dictionary = f.session.get_state_snapshot().active_request_context
	f.runtime.pump_agent()
	f.gateway.complete_pending({"kind": "response", "raw": {"context": context, "status": "ok",
		"payload": {"shape": "rectangle", "origin_cell": [1, 1], "size": [1, 1]}}})
	var ok: bool = f.session.get_state_snapshot().phase == SessionPhase.Phase.RESET_CHOICE and f.gateway.call_count == 1 \
		and f.history.snapshot().entries.size() == 1 and f.history.snapshot().entries[0].verdict == "HIT" \
		and f.runtime.get_fault().is_empty()
	f.view.queue_free()
	return ok


func _session_success_miss() -> bool:
	var session := GameSession.new(SessionRules.new(1, 1))
	var frame := WorldFrame.new(1, Vector2(96, 96), true, true)
	if not session.advance_physics_step(frame).accepted or not session.process_report_boundary(func(_b: ReportBoundary) -> void: pass, func(_b: ReportBoundary) -> void: pass):
		return false
	var context: Dictionary = session.get_state_snapshot().active_request_context
	return session.accept_guess_result(context, false) and session.get_state_snapshot().phase == SessionPhase.Phase.ROUND_END \
		and session.get_state_snapshot().round_result == SessionPhase.RoundResult.SUCCESS \
		and session.get_state_snapshot().active_request_context.is_empty()


func _runtime_protocol_faults() -> bool:
	var f: Dictionary = _runtime_fixture()
	if f.is_empty():
		return false
	await (Engine.get_main_loop() as SceneTree).physics_frame
	f.runtime.step_once(Vector2.ZERO, 1.0 / 60.0)
	var context: Dictionary = f.session.get_state_snapshot().active_request_context
	f.runtime.pump_agent()
	var wrong: Dictionary = context.duplicate(true)
	wrong.request_id += 1
	f.gateway.complete_pending({"kind": "response", "raw": {"context": wrong, "status": "ok",
		"payload": {"shape": "rectangle", "origin_cell": [1, 1], "size": [1, 1]}}})
	var bad_id: bool = not f.runtime.get_fault().is_empty() and f.session.get_state_snapshot().phase == SessionPhase.Phase.GUESS_PAUSED
	f.runtime.on_agent_result(context, "location_guess", {"kind": "response", "raw": {"context": context, "status": "ok",
		"payload": {"shape": "rectangle", "origin_cell": [1, 1], "size": [1, 1]}}})
	bad_id = bad_id and f.session.get_state_snapshot().phase == SessionPhase.Phase.GUESS_PAUSED and f.gateway.call_count == 1
	f.view.queue_free()
	var failures_stop: bool = true
	for gateway_kind: String in ["timeout", "disconnected", "empty"]:
		var t: Dictionary = _runtime_fixture()
		if t.is_empty():
			return false
		await (Engine.get_main_loop() as SceneTree).physics_frame
		t.runtime.step_once(Vector2.ZERO, 1.0 / 60.0)
		t.runtime.pump_agent()
		t.gateway.complete_pending({"kind": gateway_kind, "raw": null})
		failures_stop = failures_stop and not t.runtime.get_fault().is_empty() and t.gateway.call_count == 1 \
			and t.session.get_state_snapshot().phase == SessionPhase.Phase.GUESS_PAUSED
		t.view.queue_free()
	return bad_id and failures_stop


func _report_fault_zero_agent_calls() -> bool:
	var f: Dictionary = _runtime_fixture(true)
	if f.is_empty():
		return false
	await (Engine.get_main_loop() as SceneTree).physics_frame
	var step: Dictionary = f.runtime.step_once(Vector2.ZERO, 1.0 / 60.0)
	f.runtime.pump_agent()
	var ok: bool = step.get("ok") == false and not f.runtime.get_fault().is_empty() and f.gateway.call_count == 0
	f.view.queue_free()
	return ok


func _activate_fault_is_stop() -> bool:
	var f: Dictionary = _runtime_fixture(false, true)
	if f.is_empty():
		return false
	await (Engine.get_main_loop() as SceneTree).physics_frame
	f.runtime.step_once(Vector2.ZERO, 1.0 / 60.0)
	var guess_context: Dictionary = f.session.get_state_snapshot().active_request_context
	f.runtime.pump_agent()
	f.gateway.complete_pending({"kind": "response", "raw": {"context": guess_context, "status": "ok",
		"payload": {"shape": "rectangle", "origin_cell": [10, 1], "size": [1, 1]}}})
	var dispatch_context: Dictionary = f.session.get_state_snapshot().active_request_context
	f.runtime.pump_agent()
	f.gateway.complete_pending({"kind": "response", "raw": {"context": dispatch_context, "status": "ok",
		"payload": {"mode": "APPLY", "commands": [{"type": "MoveObstacle", "obstacle_id": 1, "anchor_cell": [8, 2]}]}}})
	var entries: Array = f.history.snapshot().entries
	var ok: bool = not f.runtime.get_fault().is_empty() and f.service.get_world_snapshot().world_revision == 0 \
		and entries.size() == 1 and entries[0].kind == "guess" and f.gateway.call_count == 2
	f.view.queue_free()
	return ok


func _runtime_retry_success() -> bool:
	var f: Dictionary = _runtime_fixture()
	if f.is_empty():
		return false
	await (Engine.get_main_loop() as SceneTree).physics_frame
	f.runtime.step_once(Vector2.ZERO, 1.0 / 60.0)
	var guess_context: Dictionary = f.session.get_state_snapshot().active_request_context
	f.runtime.pump_agent()
	f.gateway.complete_pending({"kind": "response", "raw": {"context": guess_context, "status": "ok",
		"payload": {"shape": "rectangle", "origin_cell": [10, 1], "size": [1, 1]}}})
	var first: Dictionary = f.session.get_state_snapshot().active_request_context
	f.runtime.pump_agent()
	f.gateway.complete_pending({"kind": "response", "raw": {"context": first, "status": "ok",
		"payload": {"mode": "APPLY", "commands": [{"type": "MoveObstacle", "obstacle_id": 1, "anchor_cell": [1, 1]}]}}})
	var second: Dictionary = f.session.get_state_snapshot().active_request_context
	f.runtime.pump_agent()
	var retry_request: Dictionary = f.gateway.get("_pending_request")
	var carried: bool = second.request_id != first.request_id and retry_request.previous_rejection.context == first
	f.gateway.complete_pending({"kind": "response", "raw": {"context": second, "status": "ok",
		"payload": {"mode": "APPLY", "commands": [{"type": "MoveObstacle", "obstacle_id": 1, "anchor_cell": [8, 2]}]}}})
	var state: Dictionary = f.session.get_state_snapshot()
	var entries: Array = f.history.snapshot().entries
	var ok: bool = carried and f.runtime.get_fault().is_empty() and state.phase == SessionPhase.Phase.CYCLE_START_PENDING \
		and state.dispatch_attempts == 0 and f.service.get_world_snapshot().world_revision == 1 \
		and entries.size() == 3 and entries[1].status == "REJECTED" and entries[1].context == first \
		and entries[2].status == "APPLIED" and entries[2].context == second
	f.view.queue_free()
	return ok
