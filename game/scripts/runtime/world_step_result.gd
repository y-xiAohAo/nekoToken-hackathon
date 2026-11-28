extends RefCounted
class_name WorldStepResult
## Trusted one-step package. The command service isolates and validates the candidate.


var candidate_world: WorldState
var world_frame: WorldFrame
var domain_events: Array[Dictionary] = []
var contact_requested: bool = false
var contact_id: int = 0


func _init(p_candidate_world: WorldState, p_world_frame: WorldFrame) -> void:
	candidate_world = p_candidate_world
	world_frame = p_world_frame
