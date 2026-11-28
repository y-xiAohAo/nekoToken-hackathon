extends RefCounted
class_name SessionState


var phase: SessionPhase.Phase = SessionPhase.Phase.ACTION
var round_id: int = 1
var guess_cycle_id: int = 1
var branch_id: int = 1
var active_request_context: Dictionary = {}
var active_request_type: String = ""
var dispatch_attempts: int = 0
var last_dispatch_rejection: Dictionary = {}
var frozen_guess_frame: WorldFrame
var round_result: SessionPhase.RoundResult = SessionPhase.RoundResult.NONE


func snapshot() -> Dictionary:
	return {
		"phase": phase,
		"round_id": round_id,
		"guess_cycle_id": guess_cycle_id,
		"branch_id": branch_id,
		"active_request_context": active_request_context.duplicate(true),
		"active_request_type": active_request_type,
		"dispatch_attempts": dispatch_attempts,
		"last_dispatch_rejection": last_dispatch_rejection.duplicate(true),
		"frozen_guess_frame": frozen_guess_frame.snapshot() if frozen_guess_frame != null else {},
		"round_result": round_result,
	}


static func from_snapshot(data: Dictionary) -> SessionState:
	if not DeviceRegistry.fields(data, ["phase", "round_id", "guess_cycle_id", "branch_id", "active_request_context", "active_request_type", "dispatch_attempts", "last_dispatch_rejection", "frozen_guess_frame", "round_result"]):
		return null
	for field: String in ["phase", "round_id", "guess_cycle_id", "branch_id", "dispatch_attempts", "round_result"]:
		if typeof(data[field]) != TYPE_INT:
			return null
	if data.phase < 0 or data.phase > SessionPhase.Phase.ROUND_SETUP_PAUSED or data.round_id < 1 or data.guess_cycle_id < 1 or data.branch_id < 1 or data.dispatch_attempts < 0:
		return null
	if data.round_result < SessionPhase.RoundResult.NONE or data.round_result > SessionPhase.RoundResult.FAILURE:
		return null
	if not data.active_request_context is Dictionary or not data.last_dispatch_rejection is Dictionary or not data.frozen_guess_frame is Dictionary or not data.active_request_type is String:
		return null
	var frame: WorldFrame = null
	if not data.frozen_guess_frame.is_empty():
		frame = WorldFrame.from_snapshot(data.frozen_guess_frame)
		if frame == null:
			return null
	var state := SessionState.new()
	state.phase = data.phase
	state.round_id = data.round_id
	state.guess_cycle_id = data.guess_cycle_id
	state.branch_id = data.branch_id
	state.active_request_context = data.active_request_context.duplicate(true)
	state.active_request_type = data.active_request_type
	state.dispatch_attempts = data.dispatch_attempts
	state.last_dispatch_rejection = data.last_dispatch_rejection.duplicate(true)
	state.frozen_guess_frame = frame
	state.round_result = data.round_result
	return state
