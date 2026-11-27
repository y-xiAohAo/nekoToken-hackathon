extends RefCounted
class_name SessionState


var phase: SessionPhase.Phase = SessionPhase.Phase.ACTION
var round_id: int = 1
var guess_cycle_id: int = 1
var branch_id: int = 1
var active_request_context: Dictionary = {}
var frozen_guess_frame: WorldFrame
var round_result: SessionPhase.RoundResult = SessionPhase.RoundResult.NONE


func snapshot() -> Dictionary:
	return {
		"phase": phase,
		"round_id": round_id,
		"guess_cycle_id": guess_cycle_id,
		"branch_id": branch_id,
		"active_request_context": active_request_context.duplicate(true),
		"frozen_guess_frame": frozen_guess_frame.snapshot() if frozen_guess_frame != null else {},
		"round_result": round_result,
	}
