extends RefCounted
class_name ReportBoundary


var round_id: int
var branch_id: int
var guess_cycle_id: int
var report_period_id: int
var start_tick: int
var end_tick: int
var is_guess_boundary: bool


func _init(
	p_round_id: int,
	p_branch_id: int,
	p_guess_cycle_id: int,
	p_report_period_id: int,
	p_start_tick: int,
	p_end_tick: int,
	p_is_guess_boundary: bool
) -> void:
	round_id = p_round_id
	branch_id = p_branch_id
	guess_cycle_id = p_guess_cycle_id
	report_period_id = p_report_period_id
	start_tick = p_start_tick
	end_tick = p_end_tick
	is_guess_boundary = p_is_guess_boundary


func snapshot() -> Dictionary:
	return {
		"round_id": round_id,
		"branch_id": branch_id,
		"guess_cycle_id": guess_cycle_id,
		"report_period_id": report_period_id,
		"start_tick": start_tick,
		"end_tick": end_tick,
		"is_guess_boundary": is_guess_boundary,
	}


func snapshot_copy() -> ReportBoundary:
	return ReportBoundary.new(
		round_id,
		branch_id,
		guess_cycle_id,
		report_period_id,
		start_tick,
		end_tick,
		is_guess_boundary
	)
