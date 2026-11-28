extends RefCounted
class_name ContactSessionController
## Trusted contact coordinator. The assistant only sees a session-scoped target ref.

const MAX_TEXT_LENGTH: int = 500 # Graybox fixture, not a final dialogue limit.

var _session: GameSession
var _service: WorldCommandService
var _view: RuntimeWorldView
var _assistant: SimulatedPlayerAssistant
var _route_rules: Dictionary = {}
var _open: bool = false
var _contact_id: int = 0
var _selected_id: int = 0
var _selected_ref: String = ""
var _selected_kind: String = ""
var _nonce: int = 0
var _request_used: bool = false
var _awaiting_context: Dictionary = {}
var _pending: Dictionary = {}
var _pending_context: Dictionary = {}
var _pending_revision: int = -1
var _pending_token: String = ""
var _pending_anchor: Array = []
var _pending_cells: Array = []
var _route_attempts: int = 0
var _route_locked: bool = false
var _conversation: Array[Dictionary] = []
var _receipts: Array[Dictionary] = []
var _last_message: String = ""
var _last_error: String = ""
var _fatal_error: String = ""


func _init(session: GameSession, service: WorldCommandService, view: RuntimeWorldView, assistant: SimulatedPlayerAssistant, route_rules: Dictionary = {}) -> void:
	_session = session
	_service = service
	_view = view
	_assistant = assistant
	if route_rules.is_empty():
		_route_rules = {}
	elif DeviceRegistry.fields(route_rules, ["max_route_steps", "max_route_attempts"]) \
			and typeof(route_rules.max_route_steps) == TYPE_INT and route_rules.max_route_steps >= 0 \
			and typeof(route_rules.max_route_attempts) == TYPE_INT and route_rules.max_route_attempts > 0:
		_route_rules = route_rules.duplicate(true)


func open(contact_id: int) -> bool:
	if _open or contact_id <= 0 or _session == null or _service == null or _view == null or _assistant == null:
		return false
	var state: Dictionary = _session.get_state_snapshot()
	var world: WorldState = _service.get_world_snapshot()
	var contact: Dictionary = world.registry.get_entity(contact_id) if world != null else {}
	if state.get("phase") != SessionPhase.Phase.CONTACT_PAUSED or contact.get("kind") != "contact" or contact.get("runtime_state", {}).get("used") != true:
		return false
	if not _current_context_valid():
		return false
	_open = true
	_contact_id = contact_id
	_selected_id = 0
	_selected_ref = ""
	_selected_kind = ""
	_request_used = false
	_awaiting_context = {}
	_route_attempts = 0
	_route_locked = false
	_clear_pending()
	_conversation.clear()
	_receipts.clear()
	_last_message = ""
	_last_error = ""
	_fatal_error = ""
	_view.mark_contact_target(0)
	return true


func select_displayed_camera(entity_id: int) -> bool:
	return _select_target(entity_id, "camera")


func select_displayed_target(entity_id: int) -> bool:
	return _select_target(entity_id, "")


func _select_target(entity_id: int, required_kind: String) -> bool:
	if not _contact_ready() or _route_locked or entity_id <= 0 or not _view.is_contact_target_displayed(entity_id):
		return false
	var world: WorldState = _service.get_world_snapshot()
	var kind: String = str(world.registry.get_entity(entity_id).get("kind", "")) if world != null else ""
	if kind not in ["camera", "robot"] or not required_kind.is_empty() and kind != required_kind or kind == "robot" and _route_rules.is_empty():
		return false
	_selected_id = entity_id
	_selected_kind = kind
	_nonce += 1
	_selected_ref = "contact-target-%d" % _nonce
	_clear_pending()
	_awaiting_context = {}
	if _request_used:
		_session.renew_world_request()
		_request_used = false
	_view.mark_contact_target(entity_id)
	_last_error = ""
	return true


func submit_player_text(raw_text: String) -> bool:
	if not _contact_ready() or _route_locked or not _pending.is_empty() or not _awaiting_context.is_empty():
		return false
	var player_text: String = raw_text.strip_edges()
	if player_text.is_empty() or player_text.length() > MAX_TEXT_LENGTH:
		_last_error = "INVALID_TEXT"
		return false
	if _request_used and _session.renew_world_request().is_empty():
		_last_error = "INVALID_CONTEXT"
		return false
	_request_used = true
	var context: Dictionary = _session.get_state_snapshot().active_request_context
	_conversation.append({"role": "player", "text": player_text})
	var selected: Variant = null
	var tools: Array = []
	if _selected_id > 0:
		selected = {"ref": _selected_ref, "kind": _selected_kind}
		tools.append(PlayerAssistantContract.tool_description() if _selected_kind == "camera" else PlayerAssistantContract.route_tool_description(_max_route_steps()))
	var request: Dictionary = PlayerAssistantContract.make_contact_request(context, {
		"player_text": player_text,
		"selected_target": selected,
		"available_tools": tools,
		"tool_receipts": _receipts.duplicate(true),
		"conversation": _conversation.duplicate(true),
	})
	if request.is_empty():
		_last_error = "INVALID_REQUEST"
		return false
	_awaiting_context = context.duplicate(true)
	return receive_assistant_response(_assistant.respond(request))


func receive_assistant_response(data: Variant) -> bool:
	if not _contact_ready() or _route_locked or _awaiting_context.is_empty() or not _pending.is_empty():
		return false
	var current: Dictionary = _session.get_state_snapshot().active_request_context
	if not AgentProtocol.contexts_match(current, _awaiting_context):
		_awaiting_context = {}
		return false
	var parsed: Dictionary = PlayerAssistantContract.parse_contact_response(data, _awaiting_context, _selected_ref, _selected_kind, _max_route_steps())
	_awaiting_context = {}
	if not parsed.ok:
		_last_error = str(parsed.errors[0].code)
		_receipts.append({"status": "REJECTED", "code": _last_error})
		_session.renew_world_request()
		_request_used = false
		return false
	var payload: Dictionary = parsed.value
	_last_message = payload.text
	_last_error = ""
	_conversation.append({"role": "assistant", "text": payload.text})
	if payload.kind == "PROPOSAL":
		_pending = payload.action.duplicate(true)
		_pending_context = current.duplicate(true)
		_pending_revision = _service.get_world_snapshot().world_revision
		_nonce += 1
		_pending_token = "contact-proposal-%d" % _nonce
		if _selected_kind == "robot":
			return _prepare_route_proposal()
	return true


func _prepare_route_proposal() -> bool:
	var world: WorldState = _service.get_world_snapshot()
	var cells: Array = world.expand_patrol_path(_selected_id, _pending.values.steps) if world != null else []
	if cells.is_empty():
		return _reject_route()
	_pending_anchor = cells[0].duplicate(true)
	_pending_cells = cells.duplicate(true)
	var batch: WorldCommandBatch = _make_batch([{"type": "SetPatrolPath", "robot_id": _selected_id, "cells": cells}])
	var expected: Dictionary = _pending_context.duplicate(true)
	expected["phase"] = SessionPhase.Phase.CONTACT_PAUSED
	if batch == null or _service.validate_batch(batch, expected).status != "VALID":
		return _reject_route()
	_view.set_contact_route_preview(cells)
	return true


func discard_pending_proposal() -> bool:
	if not _contact_ready() or _route_locked or _pending.is_empty():
		return false
	_clear_pending()
	_last_error = ""
	if _session.renew_world_request().is_empty():
		return false
	_request_used = false
	return true


func confirm_pending_proposal(token: String) -> bool:
	if not _contact_ready() or _route_locked or _pending.is_empty() or token.is_empty() or token != _pending_token:
		return false
	var state: Dictionary = _session.get_state_snapshot()
	var world: WorldState = _service.get_world_snapshot()
	if world == null or world.world_revision != _pending_revision \
			or not AgentProtocol.contexts_match(state.active_request_context, _pending_context) \
			or _pending.target_ref != _selected_ref or not _view.is_contact_target_displayed(_selected_id) \
			or world.registry.get_entity(_selected_id).get("kind") != _selected_kind:
		_invalidate_proposal("STALE_PROPOSAL")
		return false
	var commands: Array = []
	if _selected_kind == "camera":
		for field: String in PlayerAssistantContract.CAMERA_FIELDS:
			if _pending.values.has(field):
				commands.append({"type": "SetDeviceParameter", "id": _selected_id, "parameter": field, "value": _pending.values[field]})
	elif world.expand_patrol_path(_selected_id, _pending.values.steps) == _pending_cells:
		commands.append({"type": "SetPatrolPath", "robot_id": _selected_id, "cells": _pending_cells.duplicate(true)})
	if commands.is_empty() or commands.size() > 2:
		_invalidate_proposal("INVALID_ACTION")
		return false
	var batch: WorldCommandBatch = _make_batch(commands)
	if batch == null:
		_invalidate_proposal("INVALID_ACTION")
		return false
	var box: Dictionary = {"result": null}
	var completed: bool = _session.end_contact(func(expected: Dictionary) -> WorldCommandResult:
		if not AgentProtocol.contexts_match(expected, _pending_context):
			return WorldCommandResult.new()
		box.result = _service.commit_batch(batch, expected)
		return box.result
	)
	if completed:
		_receipts.append({"status": box.result.status, "code": ""})
		_close()
		return true
	var result: WorldCommandResult = box.result
	var internal_code: String = str(result.errors[0].code) if result != null and not result.errors.is_empty() else "CHANGE_REJECTED"
	if internal_code == "SYNC_ACTIVATION_FAILED":
		_fatal_error = internal_code
		_receipts.append({"status": "REJECTED", "code": internal_code})
		_invalidate_proposal(internal_code)
		return false
	if _selected_kind == "robot" and internal_code not in ["SYNC_PREPARE_FAILED", "STALE_WORLD", "STALE_BRANCH", "INVALID_CONTEXT"]:
		return _reject_route()
	var code: String = "STALE_PROPOSAL" if internal_code in ["STALE_WORLD", "STALE_BRANCH", "INVALID_CONTEXT"] else "CHANGE_REJECTED"
	_receipts.append({"status": "REJECTED", "code": code})
	_invalidate_proposal(code)
	return false


func _make_batch(commands: Array) -> WorldCommandBatch:
	return WorldCommandBatch.from_data({"context": _pending_context.duplicate(true), "source": "contact",
		"base_world_revision": _pending_revision, "mode": "APPLY", "commands": commands.duplicate(true)})


func _reject_route() -> bool:
	_route_attempts += 1
	_clear_pending()
	_last_error = "ROUTE_REJECTED"
	_receipts.append({"status": "REJECTED", "code": "ROUTE_REJECTED"})
	if _route_attempts >= int(_route_rules.get("max_route_attempts", 0)):
		_route_locked = true
	else:
		_session.renew_world_request()
	_request_used = false
	return false


func choose_keep_current() -> bool:
	if not _contact_ready():
		return false
	var completed: bool = _session.end_contact(func(expected: Dictionary) -> WorldCommandResult:
		var batch: WorldCommandBatch = WorldCommandBatch.from_data({
			"context": AgentProtocol.serialize_context(expected), "source": "contact",
			"base_world_revision": _service.get_world_snapshot().world_revision,
			"mode": "KEEP_CURRENT", "commands": [],
		})
		return _service.commit_batch(batch, expected)
	)
	if completed:
		_close()
		return true
	_last_error = "CHANGE_REJECTED"
	return false


func get_ui_snapshot() -> Dictionary:
	var proposal: Dictionary = {}
	if not _pending.is_empty():
		proposal = {"token": _pending_token, "type": _pending.type, "values": _pending.values.duplicate(true)}
		if _selected_kind == "robot":
			proposal["anchor"] = _pending_anchor.duplicate(true)
			proposal["preview_cells"] = _pending_cells.duplicate(true)
	return {"open": _open, "selected": _selected_id > 0, "selected_kind": _selected_kind, "proposal": proposal,
		"route_locked": _route_locked, "route_attempts_remaining": maxi(0, int(_route_rules.get("max_route_attempts", 0)) - _route_attempts),
		"message": _last_message, "error": _last_error, "fatal": _fatal_error,
		"conversation": _conversation.duplicate(true)}


func is_faulted() -> bool:
	return not _fatal_error.is_empty()


func invalidate_for_branch_change() -> void:
	_open = false
	_contact_id = 0
	_selected_id = 0
	_selected_ref = ""
	_selected_kind = ""
	_request_used = false
	_awaiting_context = {}
	_route_attempts = 0
	_route_locked = false
	_clear_pending()
	_conversation.clear()
	_receipts.clear()
	_last_message = ""
	_last_error = ""
	_view.mark_contact_target(0)


func _contact_ready() -> bool:
	return _open and _fatal_error.is_empty() and _session.get_state_snapshot().phase == SessionPhase.Phase.CONTACT_PAUSED and _current_context_valid()


func _current_context_valid() -> bool:
	var context: Variant = _session.get_state_snapshot().get("active_request_context")
	return context is Dictionary and context.get("role") == AgentProtocol.PLAYER_ASSISTANT and AgentProtocol.contexts_match(context, context)


func _max_route_steps() -> int:
	return int(_route_rules.get("max_route_steps", -1))


func _invalidate_proposal(code: String) -> void:
	_clear_pending()
	_last_error = code
	if _fatal_error.is_empty():
		_session.renew_world_request()
		_request_used = false


func _clear_pending() -> void:
	_pending = {}
	_pending_context = {}
	_pending_revision = -1
	_pending_token = ""
	_pending_anchor = []
	_pending_cells = []
	if _view != null:
		_view.set_contact_route_preview([])


func _close() -> void:
	_open = false
	_contact_id = 0
	_selected_id = 0
	_selected_ref = ""
	_selected_kind = ""
	_awaiting_context = {}
	_route_attempts = 0
	_route_locked = false
	_clear_pending()
	_view.mark_contact_target(0)
