extends RefCounted
class_name Module6RoundProtocolTests
## Module 6B's round setup wire contract, simulated proposal and fixture policy.

var passed: int = 0
var failed: int = 0


func run() -> Dictionary:
	_check(_request_is_safe_and_strict(), "round setup request contains only safe view and fixture policy")
	_check(_response_is_strict(), "round setup response rejects stale context and malformed commands")
	_check(_simulated_proposal_uses_safe_history(), "simulated setup proposes one changed existing camera field")
	_check(_world_batch_source_is_limited(), "round setup source requires a system context")
	return {"passed": passed, "failed": failed}


func _check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		push_error("MODULE 6 ROUND PROTOCOL TEST FAILED: " + label)


func _context() -> Dictionary:
	return AgentProtocol.make_request_context(AgentProtocol.SYSTEM_AGENT, 21, 2, 2, 1)


func _view() -> Dictionary:
	var world: WorldState = LevelTemplate.from_data(PrototypeConfig.level_data()).instantiate_world()
	var view := SystemAgentView.new()
	if world == null or not view.initialize(world, PrototypeConfig.system_dispatch_policy()):
		return {}
	return view.to_data()


func _request_is_safe_and_strict() -> bool:
	var context: Dictionary = _context()
	var view: Dictionary = _view()
	var policy: Dictionary = PrototypeConfig.round_setup_policy()
	var request: Dictionary = AgentProtocol.make_round_setup_request(context, view, policy)
	if request.is_empty() or request.request_type != "round_setup" or AgentProtocol.serialize_request(request).is_empty():
		return false
	var leak: Dictionary = view.duplicate(true)
	leak.world["player_position"] = [1, 1]
	var extra: Dictionary = request.duplicate(true)
	extra["secret"] = true
	var stale_reports: Dictionary = view.duplicate(true)
	stale_reports.reports.append({"fake": true})
	var wrong_role: Dictionary = context.duplicate(true)
	wrong_role.role = AgentProtocol.PLAYER_ASSISTANT
	return AgentProtocol.make_round_setup_request(context, leak, policy).is_empty() \
		and AgentProtocol.make_round_setup_request(context, stale_reports, policy).is_empty() \
		and AgentProtocol.make_round_setup_request(wrong_role, view, policy).is_empty() \
		and AgentProtocol.serialize_request(extra).is_empty() \
		and policy.commands == {"SetDeviceParameter": ["camera"]} \
		and policy.parameters == {"camera": ["scan_center"]} and policy.max_commands == 1


func _response_is_strict() -> bool:
	var context: Dictionary = _context()
	var response: Dictionary = {"context": context, "status": "ok", "payload": {"mode": "APPLY",
		"commands": [{"type": "SetDeviceParameter", "id": 1, "parameter": "scan_center", "value": 0.2}]}}
	if AgentProtocol.parse_round_setup_response(response, context).get("ok") != true:
		return false
	var wrong: Dictionary = response.duplicate(true)
	wrong.context.branch_id += 1
	var extra: Dictionary = response.duplicate(true)
	extra.payload["text"] = "apply now"
	var unknown: Dictionary = response.duplicate(true)
	unknown.payload.commands[0].type = "TeleportPlayer"
	var empty_apply: Dictionary = response.duplicate(true)
	empty_apply.payload.commands.clear()
	var keep: Dictionary = response.duplicate(true)
	keep.payload = {"mode": "KEEP_CURRENT", "commands": []}
	return AgentProtocol.parse_round_setup_response(wrong, context).get("ok") == false \
		and AgentProtocol.parse_round_setup_response(extra, context).get("ok") == false \
		and AgentProtocol.parse_round_setup_response(unknown, context).get("ok") == false \
		and AgentProtocol.parse_round_setup_response(empty_apply, context).get("ok") == false \
		and AgentProtocol.parse_round_setup_response(keep, context).get("ok") == true


func _simulated_proposal_uses_safe_history() -> bool:
	var view: Dictionary = _view()
	if view.is_empty() or view.world.cameras.is_empty():
		return false
	var context: Dictionary = _context()
	var policy: Dictionary = PrototypeConfig.round_setup_policy()
	var request: Dictionary = AgentProtocol.make_round_setup_request(context, view, policy)
	var fixture: Dictionary = {"scan_center_candidates": [-0.4, 0.4]}
	var first: Variant = SimulatedRoundSetupAgent.respond(request, fixture)
	if not first is Dictionary or AgentProtocol.parse_round_setup_response(first, context).get("ok") != true:
		return false
	var camera: Dictionary = view.world.cameras[0]
	if first.payload.commands.size() != 1 or first.payload.commands[0].id != camera.id \
			or first.payload.commands[0].value == camera.parameters.scan_center:
		return false
	var old_context: Dictionary = AgentProtocol.make_request_context(AgentProtocol.SYSTEM_AGENT, 1, 1, 1, 1)
	view.history.append({"kind": "guess", "context": old_context,
		"as_of": {"simulation_tick": 60, "report_period_id": 2},
		"origin_cell": [2, 2], "size": [1, 1], "verdict": "MISS"})
	var with_history: Dictionary = AgentProtocol.make_round_setup_request(context, view, policy)
	var second: Variant = SimulatedRoundSetupAgent.respond(with_history, fixture)
	return second is Dictionary and AgentProtocol.parse_round_setup_response(second, context).get("ok") == true \
		and second.payload.commands[0].value != first.payload.commands[0].value \
		and SimulatedRoundSetupAgent.respond(request, fixture) == first


func _world_batch_source_is_limited() -> bool:
	var context: Dictionary = _context()
	var batch: Dictionary = {"context": context, "source": "round_setup", "base_world_revision": 0,
		"mode": "APPLY", "commands": [{"type": "SetDeviceParameter", "id": 1,
			"parameter": "scan_center", "value": 0.2}]}
	var wrong: Dictionary = batch.duplicate(true)
	wrong.context.role = AgentProtocol.PLAYER_ASSISTANT
	var unknown: Dictionary = batch.duplicate(true)
	unknown.source = "model_override"
	return WorldCommandBatch.from_data(batch) != null and WorldCommandBatch.from_data(wrong) == null \
		and WorldCommandBatch.from_data(unknown) == null
