extends RefCounted
class_name CycleState


var clock: SimulationClock = SimulationClock.new()
var report_period_id: int = 0
var sealed_reports_in_guess_cycle: int = 0


func snapshot() -> Dictionary:
	return {
		"simulation_tick": clock.tick,
		"report_period_id": report_period_id,
		"sealed_reports_in_guess_cycle": sealed_reports_in_guess_cycle,
	}
