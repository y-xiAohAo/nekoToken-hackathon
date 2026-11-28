extends RefCounted
class_name RunState
## Run-wide budget, outcomes, lineage and allocation watermarks; never cycle-restored.

var _remaining_local_resets: int = 3
var _max_rounds: int = 4
var _round_id: int = 1
var _branch_id: int = 1
var _next_branch_id: int = 2
var _next_entity_id: int = 1
var _next_obstacle_id: int = 1
var _round_results: Array[Dictionary] = []
var _branch_edges: Array[Dictionary] = [{"round_id": 1, "branch_id": 1,
	"parent_branch_id": 0, "fork_tick": 0, "fork_report_period_id": 0}]


func _init(initial_world: WorldState) -> void:
	if initial_world != null:
		_next_entity_id = initial_world.next_entity_id
		_next_obstacle_id = initial_world.next_obstacle_id


func snapshot() -> Dictionary:
	return {"remaining_local_resets": _remaining_local_resets, "max_rounds": _max_rounds,
		"round_id": _round_id, "branch_id": _branch_id, "next_branch_id": _next_branch_id,
		"next_entity_id": _next_entity_id, "next_obstacle_id": _next_obstacle_id,
		"round_results": _round_results.duplicate(true), "branch_edges": _branch_edges.duplicate(true)}


func prepare_local_fork(checkpoint: CycleCheckpoint, current_world: WorldState) -> Dictionary:
	if _remaining_local_resets <= 0 or checkpoint == null or current_world == null or not current_world.validate().is_empty():
		return {}
	var source: Dictionary = checkpoint.to_data().source
	if source.round_id != _round_id or not _is_ancestor(source.branch_id, _branch_id, _round_id):
		return {}
	var prepared: Dictionary = snapshot()
	prepared.remaining_local_resets -= 1
	prepared.branch_id = _next_branch_id
	prepared.next_branch_id += 1
	prepared.next_entity_id = maxi(_next_entity_id, current_world.next_entity_id)
	prepared.next_obstacle_id = maxi(_next_obstacle_id, current_world.next_obstacle_id)
	prepared.branch_edges.append({"round_id": _round_id, "branch_id": prepared.branch_id,
		"parent_branch_id": _branch_id, "fork_tick": source.simulation_tick,
		"fork_report_period_id": source.report_period_id})
	return prepared


func prepare_next_round(result: int) -> Dictionary:
	if result not in [SessionPhase.RoundResult.SUCCESS, SessionPhase.RoundResult.FAILURE]:
		return {}
	if not _round_results.is_empty() and _round_results[-1].round_id == _round_id:
		return {}
	var prepared: Dictionary = snapshot()
	prepared.round_results.append({"round_id": _round_id, "result": result})
	prepared["next_round"] = _round_id < _max_rounds
	if prepared.next_round:
		prepared.round_id += 1
		prepared.branch_id = _next_branch_id
		prepared.next_branch_id += 1
		prepared.branch_edges.append({"round_id": prepared.round_id, "branch_id": prepared.branch_id,
			"parent_branch_id": 0, "fork_tick": 0, "fork_report_period_id": 0})
	return prepared


func accept_prepared(prepared: Dictionary) -> void:
	_remaining_local_resets = prepared.remaining_local_resets
	_round_id = prepared.round_id
	_branch_id = prepared.branch_id
	_next_branch_id = prepared.next_branch_id
	_next_entity_id = prepared.next_entity_id
	_next_obstacle_id = prepared.next_obstacle_id
	_round_results.assign(prepared.round_results.duplicate(true))
	_branch_edges.assign(prepared.branch_edges.duplicate(true))


func _is_ancestor(ancestor_id: int, branch_id: int, round_id: int) -> bool:
	var current: int = branch_id
	var seen: Dictionary = {}
	while current > 0 and not seen.has(current):
		if current == ancestor_id:
			return true
		seen[current] = true
		var parent: int = -1
		for edge: Dictionary in _branch_edges:
			if edge.round_id == round_id and edge.branch_id == current:
				parent = edge.parent_branch_id
				break
		current = parent
	return false
