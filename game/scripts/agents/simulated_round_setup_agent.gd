extends RefCounted
class_name SimulatedRoundSetupAgent
## Deterministic stand-in for a system Agent proposing a new round's initial setup.


static func respond(request: Dictionary, fixture: Dictionary) -> Variant:
	if AgentProtocol.serialize_request(request).is_empty() or request.get("request_type") != "round_setup":
		return null
	if not DeviceRegistry.plain(fixture) or not DeviceRegistry.fields(fixture, ["scan_center_candidates"]):
		return null
	var candidates: Variant = fixture.scan_center_candidates
	if not candidates is Array or candidates.is_empty():
		return null
	for value: Variant in candidates:
		if not DeviceRegistry.number(value) or value < -PI or value > PI:
			return null
	var view: Dictionary = request.view
	var cameras: Array = view.world.cameras
	if cameras.is_empty():
		return null
	var camera: Dictionary = cameras[0]
	for other: Dictionary in cameras:
		if other.id < camera.id:
			camera = other
	var current: float = float(camera.parameters.scan_center)
	var start: int = (view.history.size() + request.context.round_id) % candidates.size()
	for offset: int in candidates.size():
		var value: float = float(candidates[(start + offset) % candidates.size()])
		if is_equal_approx(value, current):
			continue
		return {"context": request.context.duplicate(true), "status": "ok", "payload": {
			"mode": "APPLY", "commands": [{"type": "SetDeviceParameter", "id": camera.id,
				"parameter": "scan_center", "value": value}]}}
	return null
