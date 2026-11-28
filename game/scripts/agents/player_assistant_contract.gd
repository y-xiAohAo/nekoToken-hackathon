extends RefCounted
class_name PlayerAssistantContract
## Strict contact DTO. Assistant prose is never interpreted as a world command.

const VIEW_FIELDS: Array[String] = ["player_text", "selected_target", "available_tools", "tool_receipts", "conversation"]
const RESPONSE_FIELDS: Array[String] = ["context", "status", "payload"]
const CAMERA_FIELDS: Array[String] = ["scan_center", "scan_half_angle"]
const DIRECTIONS: Array[String] = ["N", "E", "S", "W"]


static func tool_description() -> Dictionary:
	return {"name": "SetCameraScan", "fields": CAMERA_FIELDS.duplicate(), "max_actions": 1, "max_targets": 1}


static func route_tool_description(max_route_steps: int) -> Dictionary:
	if max_route_steps < 0:
		return {}
	return {"name": "SetPatrolRoute", "fields": ["steps"], "directions": DIRECTIONS.duplicate(),
		"max_actions": 1, "max_targets": 1, "max_route_steps": max_route_steps}


static func make_contact_request(context: Dictionary, view: Dictionary) -> Dictionary:
	if not _context_valid(context) or not DeviceRegistry.fields(view, VIEW_FIELDS) or not DeviceRegistry.plain(view):
		return {}
	if not view.player_text is String or not view.selected_target is Dictionary and view.selected_target != null:
		return {}
	if view.selected_target is Dictionary and (not DeviceRegistry.fields(view.selected_target, ["ref", "kind"]) \
			or not view.selected_target.ref is String or view.selected_target.ref.is_empty() or view.selected_target.kind not in ["camera", "robot"]):
		return {}
	if not _tools_valid(view.selected_target, view.available_tools) or not view.tool_receipts is Array or not view.conversation is Array:
		return {}
	for receipt: Variant in view.tool_receipts:
		if not DeviceRegistry.fields(receipt, ["status", "code"]) or receipt.status not in ["REJECTED", "APPLIED", "UNCHANGED"] or not receipt.code is String:
			return {}
	for line: Variant in view.conversation:
		if not DeviceRegistry.fields(line, ["role", "text"]) or line.role not in ["player", "assistant"] or not line.text is String:
			return {}
	return {"context": context.duplicate(true), "request_type": "contact", "view": view.duplicate(true)}


static func parse_contact_response(data: Variant, expected_context: Dictionary, selected_ref: String, selected_kind: String = "camera", max_route_steps: int = -1) -> Dictionary:
	if not _context_valid(expected_context) or not DeviceRegistry.fields(data, RESPONSE_FIELDS) or not DeviceRegistry.plain(data):
		return _error("INVALID_RESPONSE")
	if not _context_valid(data.context) or not AgentProtocol.contexts_match(data.context, expected_context):
		return _error("INVALID_CONTEXT")
	if data.status != "ok" or not data.payload is Dictionary:
		return _error("INVALID_RESPONSE")
	var payload: Dictionary = data.payload
	if payload.get("kind") == "MESSAGE":
		if not DeviceRegistry.fields(payload, ["kind", "text"]) or not payload.text is String:
			return _error("INVALID_RESPONSE")
		return {"ok": true, "value": payload.duplicate(true), "errors": []}
	if payload.get("kind") != "PROPOSAL" or not DeviceRegistry.fields(payload, ["kind", "text", "action"]) or not payload.text is String or not payload.action is Dictionary:
		return _error("INVALID_RESPONSE")
	var action: Dictionary = payload.action
	if not DeviceRegistry.fields(action, ["type", "target_ref", "values"]) or not action.target_ref is String \
			or action.target_ref != selected_ref or selected_ref.is_empty() or not action.values is Dictionary:
		return _error("INVALID_ACTION")
	if selected_kind == "camera" and action.type == "SetCameraScan":
		return _parse_camera(payload, action.values)
	if selected_kind == "robot" and action.type == "SetPatrolRoute" and max_route_steps >= 0:
		return _parse_route(payload, action.values, max_route_steps)
	return _error("INVALID_ACTION")


static func _parse_camera(payload: Dictionary, values: Dictionary) -> Dictionary:
	if values.is_empty() or values.size() > CAMERA_FIELDS.size():
		return _error("INVALID_ACTION")
	for field: Variant in values:
		if field not in CAMERA_FIELDS or not DeviceRegistry.number(values[field]):
			return _error("INVALID_ACTION")
	return {"ok": true, "value": payload.duplicate(true), "errors": []}


static func _parse_route(payload: Dictionary, values: Dictionary, max_route_steps: int) -> Dictionary:
	if not DeviceRegistry.fields(values, ["steps"]) or not values.steps is Array or values.steps.size() > max_route_steps:
		return _error("INVALID_ACTION")
	for step: Variant in values.steps:
		if not step is String or step not in DIRECTIONS:
			return _error("INVALID_ACTION")
	return {"ok": true, "value": payload.duplicate(true), "errors": []}


static func _tools_valid(selected: Variant, tools: Variant) -> bool:
	if not tools is Array:
		return false
	if selected == null:
		return tools.is_empty()
	if selected.kind == "camera":
		return tools == [tool_description()]
	if tools.size() != 1 or not tools[0] is Dictionary or typeof(tools[0].get("max_route_steps")) != TYPE_INT:
		return false
	return tools[0] == route_tool_description(tools[0].max_route_steps)


static func _context_valid(context: Variant) -> bool:
	return context is Dictionary and DeviceRegistry.fields(context, AgentProtocol.CONTEXT_FIELDS) and context.get("role") == AgentProtocol.PLAYER_ASSISTANT and AgentProtocol.contexts_match(context, context)


static func _error(code: String) -> Dictionary:
	return {"ok": false, "value": {}, "errors": [{"code": code}]}
