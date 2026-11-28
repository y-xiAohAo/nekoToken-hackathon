extends RefCounted
class_name SimulatedPlayerAssistant
## Deterministic local stand-in. It never receives the world or system view.

var _scan_values: Dictionary
var _route_steps: Array
var _scripted_responses: Array[Dictionary] = []


func _init(scan_values: Dictionary = {"scan_center": 0.2, "scan_half_angle": 0.4}, route_steps: Array = []) -> void:
	_scan_values = scan_values.duplicate(true)
	_route_steps = route_steps.duplicate(true)


func queue_response(response: Dictionary) -> void:
	_scripted_responses.append(response.duplicate(true))


func respond(request: Dictionary) -> Dictionary:
	if not _scripted_responses.is_empty():
		return _scripted_responses.pop_front().duplicate(true)
	if not DeviceRegistry.fields(request, ["context", "request_type", "view"]) or request.request_type != "contact" or not request.view is Dictionary:
		return {}
	var selected: Variant = request.view.get("selected_target")
	if not selected is Dictionary:
		return {"context": request.context.duplicate(true), "status": "ok", "payload": {"kind": "MESSAGE", "text": "这是模拟助手。请先在画面中标记要讨论的摄像头或机器人。"}}
	if selected.get("kind") == "robot":
		return {"context": request.context.duplicate(true), "status": "ok", "payload": {
			"kind": "PROPOSAL", "text": "这是模拟建议：重设已标记机器人的巡逻路线。请确认方向和完整预览。",
			"action": {"type": "SetPatrolRoute", "target_ref": selected.ref, "values": {"steps": _route_steps.duplicate(true)}},
		}}
	return {"context": request.context.duplicate(true), "status": "ok", "payload": {
		"kind": "PROPOSAL", "text": "这是模拟建议：调整已标记摄像头的扫描设置。请确认完整动作。",
		"action": {"type": "SetCameraScan", "target_ref": selected.ref, "values": _scan_values.duplicate(true)},
	}}
