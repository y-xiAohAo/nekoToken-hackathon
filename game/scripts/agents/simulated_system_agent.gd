extends RefCounted
class_name SimulatedSystemAgent

static func respond(request: Dictionary, script: Dictionary) -> Variant:
	if not DeviceRegistry.plain(request) or not DeviceRegistry.plain(script) or not AgentProtocol._system_context(request.get("context")):
		return null
	var kind: String = request.get("request_type", "")
	if kind not in ["location_guess", "dispatch"]:
		return null
	var key: String = "location" if kind == "location_guess" else "dispatch"
	var payload: Variant = script.get(key)
	if not payload is Dictionary:
		return null
	return {"context": request.context.duplicate(true), "status": "ok", "payload": payload.duplicate(true)}
