extends RefCounted
class_name AgentProtocol


const PROTOCOL_VERSION: String = "1"
const SYSTEM_AGENT: String = "system_agent"
const PLAYER_ASSISTANT: String = "player_assistant"
const CONTEXT_FIELDS: Array[String] = [
	"protocol_version",
	"role",
	"request_id",
	"round_id",
	"branch_id",
	"guess_cycle_id",
]
const SYSTEM_VIEW_FIELDS: Array[String] = ["static_map", "device_configuration", "reports", "history"]
const PLAYER_VIEW_FIELDS: Array[String] = ["player_text", "available_tools", "tool_receipts", "conversation"]
const SYSTEM_FORBIDDEN_KEYS: Array[String] = ["player_world_position", "contact_source"]
const PLAYER_FORBIDDEN_KEYS: Array[String] = ["static_map", "device_configuration", "reports", "system_state", "player_world_position"]


static func make_request_context(
	role: String,
	request_id: int,
	round_id: int,
	branch_id: int,
	guess_cycle_id: int
) -> Dictionary:
	return {
		"protocol_version": PROTOCOL_VERSION,
		"role": role,
		"request_id": request_id,
		"round_id": round_id,
		"branch_id": branch_id,
		"guess_cycle_id": guess_cycle_id,
	}


static func serialize_context(context: Dictionary) -> Dictionary:
	var serialized: Dictionary = {}
	for field: String in CONTEXT_FIELDS:
		if context.has(field):
			serialized[field] = context[field]
	return serialized


static func make_system_request(
	context: Dictionary,
	static_map: Dictionary,
	device_configuration: Array[Dictionary],
	reports: Array[Dictionary],
	history: Array[Dictionary] = []
) -> Dictionary:
	if context.get("role", "") != SYSTEM_AGENT:
		return {}
	return {
		"context": serialize_context(context),
		"view": {
			"static_map": static_map.duplicate(true),
			"device_configuration": device_configuration.duplicate(true),
			"reports": reports.duplicate(true),
			"history": history.duplicate(true),
		},
	}


static func make_player_assistant_request(
	context: Dictionary,
	player_text: String,
	available_tools: Array[Dictionary],
	tool_receipts: Array[Dictionary],
	conversation: Array[Dictionary]
) -> Dictionary:
	if context.get("role", "") != PLAYER_ASSISTANT:
		return {}
	return {
		"context": serialize_context(context),
		"view": {
			"player_text": player_text,
			"available_tools": available_tools.duplicate(true),
			"tool_receipts": tool_receipts.duplicate(true),
			"conversation": conversation.duplicate(true),
		},
	}


static func serialize_request(request: Dictionary) -> String:
	var context: Variant = request.get("context")
	var view: Variant = request.get("view")
	if not context is Dictionary or not view is Dictionary:
		return ""
	if request.get("request_type") == "contact":
		return _serialize_contact_request(request)
	if request.has("request_type"):
		if not DeviceRegistry.plain(request) or not _system_context(context):
			return ""
		var verified := SystemAgentView.new()
		if not verified.restore(view):
			return ""
		if request.request_type == "location_guess":
			if not DeviceRegistry.fields(request, ["context", "request_type", "view", "as_of", "constraints"]) or not _as_of_valid(request.as_of) or not _constraints_valid(request.constraints):
				return ""
		elif request.request_type == "dispatch":
			if not DeviceRegistry.fields(request, ["context", "request_type", "view", "as_of", "policy", "previous_rejection"]) or not _as_of_valid(request.as_of) or not request.policy is Dictionary:
				return ""
			if request.previous_rejection != null and not _safe_receipt_valid(request.previous_rejection, context):
				return ""
		elif request.request_type == "round_setup":
			if not DeviceRegistry.fields(request, ["context", "request_type", "view", "policy"]) \
					or context.guess_cycle_id != 1 or not view.reports.is_empty() \
					or not _round_setup_policy_valid(request.policy):
				return ""
		else:
			return ""
		return JSON.stringify(request)
	if not _is_valid_context(context):
		return ""
	var role: String = str(context.get("role", ""))
	var fields: Array[String]
	var forbidden: Array[String]
	if role == SYSTEM_AGENT:
		fields = SYSTEM_VIEW_FIELDS
		forbidden = SYSTEM_FORBIDDEN_KEYS
	elif role == PLAYER_ASSISTANT:
		fields = PLAYER_VIEW_FIELDS
		forbidden = PLAYER_FORBIDDEN_KEYS
	else:
		return ""
	var safe_view: Dictionary = {}
	for field: String in fields:
		if not view.has(field) or _contains_forbidden_key(view[field], forbidden):
			return ""
		safe_view[field] = view[field]
	return JSON.stringify({"context": serialize_context(context), "view": safe_view})


static func _serialize_contact_request(request: Dictionary) -> String:
	var context: Variant = request.get("context")
	var view: Variant = request.get("view")
	if not DeviceRegistry.plain(request) or not DeviceRegistry.fields(request, ["context", "request_type", "view"]) \
			or not _is_valid_context(context) or context.role != PLAYER_ASSISTANT or not view is Dictionary:
		return ""
	var fields: Array[String] = ["player_text", "selected_target", "available_tools", "tool_receipts", "conversation"]
	if not DeviceRegistry.fields(view, fields):
		return ""
	var forbidden: Array[String] = PLAYER_FORBIDDEN_KEYS.duplicate()
	forbidden.append_array(["cell", "cells", "anchor", "patrol_path", "position", "internal_id", "entity_id", "robot_id", "id", "map", "system_view"])
	if _contains_forbidden_key(view, forbidden):
		return ""
	return JSON.stringify(request)


static func _contains_forbidden_key(value: Variant, forbidden: Array[String]) -> bool:
	if value is Dictionary:
		for key: Variant in value:
			if str(key) in forbidden or _contains_forbidden_key(value[key], forbidden):
				return true
	elif value is Array:
		for item: Variant in value:
			if _contains_forbidden_key(item, forbidden):
				return true
	return false


static func _is_valid_context(context: Dictionary) -> bool:
	for field: String in CONTEXT_FIELDS:
		if not context.has(field):
			return false
	if context["protocol_version"] != PROTOCOL_VERSION:
		return false
	if context["role"] not in [SYSTEM_AGENT, PLAYER_ASSISTANT]:
		return false
	for field: String in ["request_id", "round_id", "branch_id", "guess_cycle_id"]:
		if typeof(context[field]) != TYPE_INT or context[field] < 1:
			return false
	return true


static func contexts_match(actual: Dictionary, expected: Dictionary) -> bool:
	if not _is_valid_context(actual) or not _is_valid_context(expected):
		return false
	for field: String in CONTEXT_FIELDS:
		if not actual.has(field) or not expected.has(field) or actual[field] != expected[field]:
			return false
	return true


static func response_matches(response: Dictionary, expected_context: Dictionary) -> bool:
	if not response.has("context") or not response.has("status") or not response.has("payload"):
		return false
	if response["status"] != "ok":
		return false
	if not response["context"] is Dictionary:
		return false
	return contexts_match(response["context"], expected_context)


static func make_location_request(context: Dictionary, view: Dictionary, as_of: Dictionary, constraints: Dictionary) -> Dictionary:
	if not _system_context(context) or not _as_of_valid(as_of) or not _constraints_valid(constraints):
		return {}
	var verified := SystemAgentView.new()
	if not verified.restore(view):
		return {}
	return {"context": context.duplicate(true), "request_type": "location_guess", "view": verified.to_data(),
		"as_of": as_of.duplicate(true), "constraints": constraints.duplicate(true)}


static func make_dispatch_request(context: Dictionary, view: Dictionary, as_of: Dictionary, policy: Dictionary, previous_rejection: Variant) -> Dictionary:
	if not _system_context(context) or not _as_of_valid(as_of) or not DeviceRegistry.plain(policy) or not policy is Dictionary:
		return {}
	if previous_rejection != null and not _safe_receipt_valid(previous_rejection, context):
		return {}
	var verified := SystemAgentView.new()
	if not verified.restore(view):
		return {}
	return {"context": context.duplicate(true), "request_type": "dispatch", "view": verified.to_data(),
		"as_of": as_of.duplicate(true), "policy": policy.duplicate(true),
		"previous_rejection": previous_rejection.duplicate(true) if previous_rejection is Dictionary else null}


static func make_round_setup_request(context: Dictionary, view: Dictionary, policy: Dictionary) -> Dictionary:
	if not _system_context(context) or context.guess_cycle_id != 1 or not _round_setup_policy_valid(policy):
		return {}
	var verified := SystemAgentView.new()
	if not verified.restore(view) or not verified.to_data().reports.is_empty():
		return {}
	return {"context": serialize_context(context), "request_type": "round_setup",
		"view": verified.to_data(), "policy": policy.duplicate(true)}


static func parse_round_setup_response(raw: Variant, expected_context: Dictionary) -> Dictionary:
	var failure: Dictionary = {"ok": false, "payload": {}, "error": "INVALID_ROUND_SETUP_RESPONSE"}
	if not _response_valid(raw, expected_context) or expected_context.guess_cycle_id != 1 \
			or not DeviceRegistry.fields(raw.payload, ["mode", "commands"]):
		return failure
	var payload: Dictionary = raw.payload
	if payload.mode not in ["APPLY", "KEEP_CURRENT"] or not payload.commands is Array or payload.commands.size() > 1 \
			or (payload.mode == "KEEP_CURRENT") != payload.commands.is_empty():
		return failure
	for command: Variant in payload.commands:
		if not WorldCommandBatch.command_valid(command):
			return failure
	return {"ok": true, "payload": payload.duplicate(true), "error": ""}


static func parse_location_response(raw: Variant, expected_context: Dictionary, constraints: Dictionary, grid_size: Vector2i) -> Dictionary:
	var failure: Dictionary = {"ok": false, "payload": {}, "error": "INVALID_LOCATION_RESPONSE"}
	if not _response_valid(raw, expected_context) or not _constraints_valid(constraints) or grid_size.x <= 0 or grid_size.y <= 0:
		return failure
	var payload: Variant = raw.payload
	if not DeviceRegistry.fields(payload, ["shape", "origin_cell", "size"]) or payload.shape != "rectangle" or not DeviceRegistry.cell(payload.origin_cell) or not DeviceRegistry.cell(payload.size):
		return failure
	var x: int = payload.origin_cell[0]
	var y: int = payload.origin_cell[1]
	var width: int = payload.size[0]
	var height: int = payload.size[1]
	if x < 0 or y < 0 or width <= 0 or height <= 0 or width > constraints.max_width or height > constraints.max_height:
		return failure
	if width > grid_size.x or height > grid_size.y or x > grid_size.x - width or y > grid_size.y - height:
		return failure
	if width * height > constraints.max_cells:
		return failure
	return {"ok": true, "payload": payload.duplicate(true), "error": ""}


static func parse_dispatch_response(raw: Variant, expected_context: Dictionary) -> Dictionary:
	var failure: Dictionary = {"ok": false, "payload": {}, "error": "INVALID_DISPATCH_RESPONSE"}
	if not _response_valid(raw, expected_context) or not DeviceRegistry.fields(raw.payload, ["mode", "commands"]):
		return failure
	var payload: Dictionary = raw.payload
	if payload.mode not in ["APPLY", "KEEP_CURRENT"] or not payload.commands is Array or (payload.mode == "KEEP_CURRENT") != payload.commands.is_empty():
		return failure
	for command: Variant in payload.commands:
		if not WorldCommandBatch.command_valid(command):
			return failure
	return {"ok": true, "payload": payload.duplicate(true), "error": ""}


static func _system_context(context: Variant) -> bool:
	return DeviceRegistry.fields(context, CONTEXT_FIELDS) and _is_valid_context(context) and context.role == SYSTEM_AGENT


static func _response_valid(raw: Variant, expected_context: Dictionary) -> bool:
	return DeviceRegistry.plain(raw) and DeviceRegistry.fields(raw, ["context", "status", "payload"]) \
		and _system_context(raw.context) and _system_context(expected_context) \
		and contexts_match(raw.context, expected_context) and raw.status == "ok"


static func _as_of_valid(as_of: Variant) -> bool:
	return DeviceRegistry.fields(as_of, ["simulation_tick", "report_period_id"]) \
		and typeof(as_of.simulation_tick) == TYPE_INT and as_of.simulation_tick >= 0 \
		and typeof(as_of.report_period_id) == TYPE_INT and as_of.report_period_id >= 0


static func _constraints_valid(constraints: Variant) -> bool:
	if not DeviceRegistry.fields(constraints, ["shape", "max_width", "max_height", "max_cells"]) or constraints.shape != "rectangle":
		return false
	for field: String in ["max_width", "max_height", "max_cells"]:
		if typeof(constraints[field]) != TYPE_INT or constraints[field] <= 0:
			return false
	return true


static func _round_setup_policy_valid(policy: Variant) -> bool:
	return DeviceRegistry.plain(policy) and DeviceRegistry.fields(policy, ["commands", "parameters", "max_commands"]) \
		and policy.commands == {"SetDeviceParameter": ["camera"]} \
		and policy.parameters == {"camera": ["scan_center"]} and policy.max_commands == 1


static func _safe_receipt_valid(receipt: Variant, current_context: Dictionary) -> bool:
	if not DeviceRegistry.plain(receipt) or not DeviceRegistry.fields(receipt, ["status", "context", "errors"]) or receipt.status != "REJECTED":
		return false
	if not _system_context(receipt.context) or not receipt.errors is Array or receipt.errors.is_empty():
		return false
	if receipt.context.round_id != current_context.round_id or receipt.context.branch_id != current_context.branch_id or receipt.context.guess_cycle_id != current_context.guess_cycle_id or receipt.context.request_id >= current_context.request_id:
		return false
	for error: Variant in receipt.errors:
		if not DeviceRegistry.fields(error, ["code", "command_index"]) or not error.code is String or error.code.is_empty() or typeof(error.command_index) != TYPE_INT or error.command_index < -1:
			return false
	return true
