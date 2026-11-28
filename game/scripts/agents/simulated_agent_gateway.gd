extends RefCounted
class_name SimulatedAgentGateway

var call_count: int = 0
var _script: Dictionary = {}
var _auto_complete: bool = false
var _pending_request: Dictionary = {}
var _completion: Callable

func _init(script: Dictionary = {}, auto_complete: bool = false) -> void:
	_script = script.duplicate(true) if DeviceRegistry.plain(script) else {}
	_auto_complete = auto_complete


func submit(request: Dictionary, completion: Callable) -> bool:
	if not _pending_request.is_empty() or not completion.is_valid() or not DeviceRegistry.plain(request) or not AgentProtocol._system_context(request.get("context")):
		return false
	if request.get("request_type") not in ["location_guess", "dispatch"]:
		return false
	_pending_request = request.duplicate(true)
	_completion = completion
	call_count += 1
	if _auto_complete:
		call_deferred("_auto_complete_pending")
	return true

func complete_pending(result: Variant) -> bool:
	if _pending_request.is_empty() or not result is Dictionary or not DeviceRegistry.fields(result, ["kind", "raw"]):
		return false
	if result.kind not in ["response", "timeout", "disconnected", "empty"]:
		return false
	var completion: Callable = _completion
	_pending_request = {}
	_completion = Callable()
	completion.call(result.duplicate(true))
	return true


func _auto_complete_pending() -> void:
	if _pending_request.is_empty():
		return
	var raw: Variant = SimulatedSystemAgent.respond(_pending_request, _script)
	complete_pending({"kind": "response" if raw != null else "empty", "raw": raw})
