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


static func from_snapshot(data: Dictionary) -> CycleState:
	if not DeviceRegistry.fields(data, ["simulation_tick", "report_period_id", "sealed_reports_in_guess_cycle"]):
		return null
	for field: String in ["simulation_tick", "report_period_id", "sealed_reports_in_guess_cycle"]:
		if typeof(data[field]) != TYPE_INT or data[field] < 0:
			return null
	var state := CycleState.new()
	state.clock.tick = data.simulation_tick
	state.report_period_id = data.report_period_id
	state.sealed_reports_in_guess_cycle = data.sealed_reports_in_guess_cycle
	return state
