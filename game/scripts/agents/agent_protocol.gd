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
