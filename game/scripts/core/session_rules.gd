extends RefCounted
class_name SessionRules


var ticks_per_report_period: int
var report_periods_per_guess_cycle: int


func _init(p_ticks_per_report_period: int, p_report_periods_per_guess_cycle: int) -> void:
	ticks_per_report_period = p_ticks_per_report_period
	report_periods_per_guess_cycle = p_report_periods_per_guess_cycle


func is_valid() -> bool:
	return ticks_per_report_period > 0 and report_periods_per_guess_cycle > 0
