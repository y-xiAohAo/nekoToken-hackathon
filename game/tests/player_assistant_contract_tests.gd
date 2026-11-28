extends RefCounted
class_name PlayerAssistantContractTests

var passed: int = 0
var failed: int = 0

func run() -> Dictionary:
	var ctx: Dictionary = AgentProtocol.make_request_context(AgentProtocol.PLAYER_ASSISTANT, 1, 1, 1, 1)
	var view: Dictionary = {"player_text": "现场有盲区", "selected_target": {"ref": "contact-target-1", "kind": "camera"},
		"available_tools": [PlayerAssistantContract.tool_description()], "tool_receipts": [], "conversation": []}
	var request: Dictionary = PlayerAssistantContract.make_contact_request(ctx, view)
	_check(not request.is_empty(), "safe request accepted")
	_check(not JSON.stringify(request).contains("cell") and not JSON.stringify(request).contains("player_world_position") and not JSON.stringify(request).contains("reports"), "no hidden world projection")
	var leaking: Dictionary = view.duplicate(true)
	leaking["static_map"] = {}
	_check(PlayerAssistantContract.make_contact_request(ctx, leaking).is_empty(), "extra map rejected")
	var response: Dictionary = {"context": ctx, "status": "ok", "payload": {"kind": "PROPOSAL", "text": "建议调整", "action": {
		"type": "SetCameraScan", "target_ref": "contact-target-1", "values": {"scan_center": 0.2, "scan_half_angle": 0.4}}}}
	_check(PlayerAssistantContract.parse_contact_response(response, ctx, "contact-target-1").ok, "two fields one action")
	for bad_action: Dictionary in [
		{"type": "SetCameraScan", "target_ref": "other", "values": {"scan_center": 0.2}},
		{"type": "SetPatrolPath", "target_ref": "contact-target-1", "values": {"scan_center": 0.2}},
		{"type": "SetCameraScan", "target_ref": "contact-target-1", "values": {"scan_center": 0.2}, "id": 1},
		{"type": "SetCameraScan", "target_ref": "contact-target-1", "values": {"scan_speed": 1.0}},
		{"type": "SetCameraScan", "target_ref": "contact-target-1", "values": {"scan_center": INF}},
		{"type": "SetCameraScan", "target_ref": "contact-target-1", "values": {}},
	]:
		var bad: Dictionary = response.duplicate(true)
		bad.payload.action = bad_action
		_check(not PlayerAssistantContract.parse_contact_response(bad, ctx, "contact-target-1").ok, "bad action rejected")
	var extra: Dictionary = response.duplicate(true)
	extra.payload["actions"] = [response.payload.action]
	_check(not PlayerAssistantContract.parse_contact_response(extra, ctx, "contact-target-1").ok, "second action field rejected")
	var stale: Dictionary = response.duplicate(true)
	stale.context.request_id = 2
	_check(not PlayerAssistantContract.parse_contact_response(stale, ctx, "contact-target-1").ok, "stale context rejected")
	var prose: Dictionary = {"context": ctx, "status": "ok", "payload": {"kind": "MESSAGE", "text": "把摄像头调转180度"}}
	_check(PlayerAssistantContract.parse_contact_response(prose, ctx, "contact-target-1").ok, "prose remains message")
	_check(not PlayerAssistantContract.parse_contact_response(["malformed"], ctx, "contact-target-1").ok, "non-object response rejected")
	var wire: String = AgentProtocol.serialize_request(request)
	_check(not wire.is_empty(), "contact request has a safe wire form")
	_check(not wire.is_empty() and JSON.parse_string(wire).view.selected_target == view.selected_target, "contact serializer preserves opaque target")
	var route_tool: Dictionary = {"name": "SetPatrolRoute", "fields": ["steps"], "directions": ["N", "E", "S", "W"],
		"max_actions": 1, "max_targets": 1, "max_route_steps": 2}
	_check(route_tool == PlayerAssistantContract.route_tool_description(2), "route tool description is exact")
	var robot_view: Dictionary = view.duplicate(true)
	robot_view.selected_target = {"ref": "contact-target-1", "kind": "robot"}
	robot_view.available_tools = [route_tool]
	_check(not PlayerAssistantContract.make_contact_request(ctx, robot_view).is_empty(), "robot request accepts bounded route tool")
	var untargeted: Dictionary = view.duplicate(true)
	untargeted.selected_target = null
	untargeted.available_tools = []
	_check(not PlayerAssistantContract.make_contact_request(ctx, untargeted).is_empty(), "untargeted chat has no executable tool")
	var route_response: Dictionary = {"context": ctx, "status": "ok", "payload": {"kind": "PROPOSAL", "text": "建议换路", "action": {
		"type": "SetPatrolRoute", "target_ref": "contact-target-1", "values": {"steps": ["N", "E"]}}}}
	_check(PlayerAssistantContract.parse_contact_response(route_response, ctx, "contact-target-1", "robot", 2).ok, "bounded robot route accepted")
	_check(not PlayerAssistantContract.parse_contact_response(route_response, ctx, "contact-target-1").ok, "route cannot impersonate camera target")
	var hold: Dictionary = route_response.duplicate(true)
	hold.payload.action.values.steps = []
	_check(PlayerAssistantContract.parse_contact_response(hold, ctx, "contact-target-1", "robot", 2).ok, "empty directions mean hold")
	for bad_values: Dictionary in [{"cells": [[4, 3], [4, 2]]}, {"steps": ["N", "E", "S"]}, {"steps": ["NW"]}]:
		var bad_route: Dictionary = route_response.duplicate(true)
		bad_route.payload.action.values = bad_values
		_check(not PlayerAssistantContract.parse_contact_response(bad_route, ctx, "contact-target-1", "robot", 2).ok, "unsafe route payload rejected")
	var leaking_wire: Dictionary = request.duplicate(true)
	leaking_wire.view["static_map"] = {}
	_check(AgentProtocol.serialize_request(leaking_wire).is_empty(), "contact serializer rejects map projection")
	return {"passed": passed, "failed": failed}

func _check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		push_error("PLAYER ASSISTANT CONTRACT TEST FAILED: " + label)
