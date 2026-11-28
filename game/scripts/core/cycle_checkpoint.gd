extends RefCounted
class_name CycleCheckpoint
## Immutable, plain-data start of one guess cycle. Persistent Agent history stays outside.

const FIELDS: Array[String] = ["schema_version", "source", "world", "session", "cycle", "sensing", "active_report_count"]
const SOURCE_FIELDS: Array[String] = ["round_id", "branch_id", "guess_cycle_id", "simulation_tick", "report_period_id"]

var _data: Dictionary = {}


static func capture(world: WorldState, session: GameSession, sensing: RuntimeSensingCoordinator) -> CycleCheckpoint:
	if world == null or session == null or sensing == null:
		return null
	var state: Dictionary = session.get_state_snapshot()
	var cycle: Dictionary = session.get_cycle_snapshot()
	var sensed: Dictionary = sensing.snapshot()
	if state.is_empty() or cycle.is_empty() or sensed.is_empty():
		return null
	var source: Dictionary = {"round_id": state.round_id, "branch_id": state.branch_id,
		"guess_cycle_id": state.guess_cycle_id, "simulation_tick": cycle.simulation_tick,
		"report_period_id": cycle.report_period_id}
	return from_data({"schema_version": 1, "source": source, "world": world.to_snapshot(),
		"session": state, "cycle": cycle, "sensing": sensed,
		"active_report_count": sensed.get("system_view", {}).get("reports", []).size()})


static func from_data(data: Dictionary) -> CycleCheckpoint:
	if not _valid(data):
		return null
	var result := CycleCheckpoint.new()
	result._data = data.duplicate(true)
	return result


func to_data() -> Dictionary:
	return _data.duplicate(true)


static func _valid(data: Dictionary) -> bool:
	if not DeviceRegistry.plain(data) or not DeviceRegistry.fields(data, FIELDS) or data.schema_version != 1:
		return false
	if not DeviceRegistry.fields(data.source, SOURCE_FIELDS) or not data.session is Dictionary or not data.cycle is Dictionary or not data.sensing is Dictionary:
		return false
	var source: Dictionary = data.source
	for field: String in SOURCE_FIELDS:
		if typeof(source[field]) != TYPE_INT or source[field] < (0 if field in ["simulation_tick", "report_period_id"] else 1):
			return false
	var state: Dictionary = data.session
	var cycle: Dictionary = data.cycle
	if not DeviceRegistry.fields(state, ["phase", "round_id", "guess_cycle_id", "branch_id", "active_request_context", "active_request_type", "dispatch_attempts", "last_dispatch_rejection", "frozen_guess_frame", "round_result"]):
		return false
	if not DeviceRegistry.fields(cycle, ["simulation_tick", "report_period_id", "sealed_reports_in_guess_cycle"]):
		return false
	if state.round_id != source.round_id or state.branch_id != source.branch_id or state.guess_cycle_id != source.guess_cycle_id or cycle.simulation_tick != source.simulation_tick or cycle.report_period_id != source.report_period_id:
		return false
	if state.phase != SessionPhase.Phase.CYCLE_START_PENDING and not (state.phase == SessionPhase.Phase.ACTION and source.simulation_tick == 0 and source.guess_cycle_id == 1):
		return false
	if not state.active_request_context is Dictionary or not state.active_request_context.is_empty() or state.active_request_type != "" or not state.frozen_guess_frame is Dictionary or not state.frozen_guess_frame.is_empty():
		return false
	if state.dispatch_attempts != 0 or not state.last_dispatch_rejection is Dictionary or not state.last_dispatch_rejection.is_empty() or state.round_result != SessionPhase.RoundResult.NONE or cycle.sealed_reports_in_guess_cycle != 0:
		return false
	if typeof(data.active_report_count) != TYPE_INT or data.active_report_count < 0 or not DeviceRegistry.fields(data.sensing, RuntimeSensingCoordinator.SNAPSHOT_FIELDS):
		return false
	var sensed: Dictionary = data.sensing
	if sensed.round_id != source.round_id or sensed.branch_id != source.branch_id or sensed.ticks_per_report_period <= 0 or not sensed.system_view is Dictionary or not sensed.system_view.get("reports") is Array:
		return false
	if data.active_report_count != sensed.system_view.reports.size() or data.active_report_count != source.report_period_id:
		return false
	if sensed.device_buffer.get("last_sealed_period_id") != source.report_period_id:
		return false
	var world: WorldState = WorldState.from_snapshot(data.world)
	if world == null:
		return false
	# Restoring into a private coordinator validates pending records, sidecars and public reports.
	var probe := RuntimeSensingCoordinator.new()
	var context: Dictionary = {"round_id": source.round_id, "branch_id": source.branch_id,
		"guess_cycle_id": 1, "report_cycle_id": 1,
		"sense_tick": 0}
	if not probe.initialize_round(world, context, sensed.ticks_per_report_period, sensed.system_view.world.dispatch_rules):
		return false
	if not probe.restore(sensed):
		return false
	for entry: Variant in sensed.device_buffer.pending:
		var tick: int = entry.data.sense_tick if entry.record_type == "visual" else entry.data.event_tick
		if tick != source.simulation_tick:
			return false
	for goal: Variant in sensed.goal_pending:
		if goal.event_tick != source.simulation_tick:
			return false
	return true
