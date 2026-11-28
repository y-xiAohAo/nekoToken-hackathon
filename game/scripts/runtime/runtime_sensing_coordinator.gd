extends RefCounted
class_name RuntimeSensingCoordinator
## Commit-gated sensing, device/goal aggregation, and role-safe publication.

const SNAPSHOT_FIELDS: Array[String] = ["ticks_per_report_period", "round_id", "branch_id", "visual_states", "device_buffer", "goal_pending", "device_sidecars", "system_view"]
const CONTEXT_FIELDS: Array[String] = ["round_id", "branch_id", "guess_cycle_id", "report_cycle_id", "sense_tick"]
const DOMAIN_FIELDS: Array[String] = ["goal_id", "tick", "type", "progress"]

var _n: int = 0
var _round_id: int = 0
var _branch_id: int = 0
var _visual_states: Dictionary = {}
var _device_buffer: ReportBuffer
var _goal_pending: Array[Dictionary] = []
var _device_sidecars: Array[Dictionary] = []
var _view: SystemAgentView
var _last_world: WorldState
var _prepared: SensingStepResult
var _prepared_context: Dictionary = {}
var _prepared_world: Dictionary = {}
var _staged: Dictionary = {}

func initialize_round(world: WorldState, context: Dictionary, ticks_per_report_period: int) -> bool:
	if _n != 0 or world == null or not DeviceRegistry.fields(context, CONTEXT_FIELDS) or context.sense_tick != 0 or ticks_per_report_period <= 0:
		return false
	var result: SensingStepResult = SensingKernel.initialize_round(world, context, ticks_per_report_period)
	if not result.succeeded():
		return false
	var view := SystemAgentView.new()
	if not view.initialize(world):
		return false
	var buffer := ReportBuffer.new(ticks_per_report_period)
	if not buffer.append_all(result.visual_records, result.plate_records):
		return false
	var sidecars: Array[Dictionary] = _sidecars_for(result, world)
	if sidecars.size() != result.visual_records.size() + result.plate_records.size():
		return false
	var committed_copy: WorldState = world.snapshot_copy()
	if committed_copy == null:
		return false
	_n = ticks_per_report_period
	_round_id = context.round_id
	_branch_id = context.branch_id
	_visual_states = SensingKernel.copy_visual_states(result.next_visual_states)
	_device_buffer = buffer
	_device_sidecars = sidecars
	_view = view
	_last_world = committed_copy
	return true

func prepare_step(previous_actor_cells: Dictionary, candidate: WorldState, context: Dictionary) -> SensingStepResult:
	_clear_prepared()
	if _n <= 0 or candidate == null or not DeviceRegistry.fields(context, CONTEXT_FIELDS) or context.round_id != _round_id or context.branch_id != _branch_id or not _staged.is_empty():
		return _error("INVALID_CONTEXT")
	var result: SensingStepResult = SensingKernel.step(_visual_states, previous_actor_cells, candidate, context, _n)
	if not result.succeeded():
		return result
	_prepared = result.snapshot_copy()
	_prepared_context = context.duplicate(true)
	_prepared_world = candidate.to_snapshot()
	return result

func commit_step(prepared: SensingStepResult, domain_events: Array[Dictionary], committed_world: WorldState, context: Dictionary) -> bool:
	if _prepared == null or prepared == null or committed_world == null or context != _prepared_context or committed_world.to_snapshot() != _prepared_world:
		_clear_prepared()
		return false
	if not prepared.succeeded() or _step_data(prepared) != _step_data(_prepared):
		_clear_prepared()
		return false
	var restored: Dictionary = SensingKernel.restore_visual_states(prepared.next_visual_states, committed_world)
	if not restored.ok:
		_clear_prepared()
		return false
	var buffer := ReportBuffer.new(_n)
	if not buffer.restore(_device_buffer.snapshot()) or not buffer.append_all(prepared.visual_records, prepared.plate_records):
		_clear_prepared()
		return false
	var sidecars: Array[Dictionary] = _sidecars_for(prepared, committed_world)
	if sidecars.size() != prepared.visual_records.size() + prepared.plate_records.size():
		_clear_prepared()
		return false
	var goals: Array[Dictionary] = _goal_pending.duplicate(true)
	for event: Dictionary in domain_events:
		if not DeviceRegistry.fields(event, DOMAIN_FIELDS) or typeof(event.goal_id) != TYPE_INT or typeof(event.tick) != TYPE_INT or event.tick != context.sense_tick or not DeviceRegistry.number(event.progress) or event.progress < 0.0 or event.progress > 1.0:
			_clear_prepared()
			return false
		if committed_world.registry.get_entity(event.goal_id).get("kind") != "goal":
			_clear_prepared()
			return false
		var goal: GoalOperationRecord = GoalOperationRecord.from_data({"round_id": context.round_id, "branch_id": context.branch_id,
			"guess_cycle_id": context.guess_cycle_id, "report_cycle_id": context.report_cycle_id,
			"goal_id": event.goal_id, "event_tick": event.tick, "type": event.type})
		if goal == null or goal.report_cycle_id != goal.event_tick / _n + 1 or goal.report_cycle_id <= _device_buffer.snapshot().last_sealed_period_id:
			_clear_prepared()
			return false
		goals.append(goal.to_data())
	var committed_copy: WorldState = committed_world.snapshot_copy()
	if committed_copy == null:
		_clear_prepared()
		return false
	_device_buffer = buffer
	_goal_pending = goals
	_device_sidecars.append_array(sidecars)
	_visual_states = restored.states
	_last_world = committed_copy
	_clear_prepared()
	return true

func seal_report_batch(boundary: ReportBoundary) -> bool:
	_staged.clear()
	if _n <= 0 or boundary == null or boundary.round_id != _round_id or boundary.branch_id != _branch_id:
		return false
	var buffer := ReportBuffer.new(_n)
	if not buffer.restore(_device_buffer.snapshot()):
		return false
	var device_batch: SensingReportBatch = buffer.seal(boundary)
	if device_batch == null:
		return false
	var selected_sidecars: Array[Dictionary] = []
	var remaining_sidecars: Array[Dictionary] = []
	for entry: Dictionary in _device_sidecars:
		var tick: int = _entry_tick(entry)
		if tick < boundary.start_tick:
			return false
		if tick < boundary.end_tick:
			selected_sidecars.append(entry.duplicate(true))
		else:
			remaining_sidecars.append(entry.duplicate(true))
	_sort_entries(selected_sidecars)
	if selected_sidecars.size() != device_batch.records.size():
		return false
	for index: int in selected_sidecars.size():
		if selected_sidecars[index].record_type != device_batch.records[index].record_type or selected_sidecars[index].data != device_batch.records[index].data:
			return false
	var selected_goals: Array[Dictionary] = []
	var remaining_goals: Array[Dictionary] = []
	for raw_goal: Dictionary in _goal_pending:
		var goal: GoalOperationRecord = GoalOperationRecord.from_data(raw_goal)
		if goal == null or goal.event_tick < boundary.start_tick:
			return false
		if goal.event_tick < boundary.end_tick:
			if goal.report_cycle_id != boundary.report_period_id or goal.round_id != boundary.round_id or goal.branch_id != boundary.branch_id:
				return false
			selected_goals.append({"record_type": "goal_operation", "data": goal.to_data()})
		else:
			remaining_goals.append(raw_goal.duplicate(true))
	var combined: Array[Dictionary] = selected_sidecars
	combined.append_array(selected_goals)
	_sort_entries(combined)
	var batch: UnifiedReportBatch = UnifiedReportBatch.from_data({"round_id": boundary.round_id, "branch_id": boundary.branch_id,
		"guess_cycle_id": boundary.guess_cycle_id, "report_period_id": boundary.report_period_id,
		"start_tick": boundary.start_tick, "end_tick": boundary.end_tick, "records": combined})
	if batch == null:
		return false
	_staged = {"buffer": buffer, "goal_pending": remaining_goals, "device_sidecars": remaining_sidecars, "batch": batch}
	return true

func update_system_view(boundary: ReportBoundary, committed_world: WorldState) -> bool:
	if _staged.is_empty() or committed_world == null or boundary == null or _staged.batch.report_period_id != boundary.report_period_id or _last_world == null or committed_world.to_snapshot() != _last_world.to_snapshot():
		return false
	var view := SystemAgentView.new()
	if not view.restore(_view.snapshot()) or not view.update_configuration(committed_world) or not view.append_batch(_staged.batch):
		return false
	_staged["view"] = view
	return true

func finish_report_boundary() -> bool:
	if _staged.is_empty() or not _staged.has("view"):
		return false
	_device_buffer = _staged.buffer
	_goal_pending = _staged.goal_pending
	_device_sidecars = _staged.device_sidecars
	_view = _staged.view
	_staged.clear()
	return true

func discard_report_boundary() -> void:
	_staged.clear()

func get_system_view() -> Dictionary:
	return _view.to_data() if _view != null else {}

func get_ticks_per_report_period() -> int:
	return _n

func snapshot() -> Dictionary:
	if _n <= 0:
		return {}
	var plain_states: Dictionary = {}
	for id: int in _visual_states:
		var state: Dictionary = _visual_states[id].duplicate(true)
		if state.visible_cell is Vector2i:
			state.visible_cell = [state.visible_cell.x, state.visible_cell.y]
		plain_states[str(id)] = state
	return {"ticks_per_report_period": _n, "round_id": _round_id, "branch_id": _branch_id,
		"visual_states": plain_states, "device_buffer": _device_buffer.snapshot(),
		"goal_pending": _goal_pending.duplicate(true), "device_sidecars": _device_sidecars.duplicate(true),
		"system_view": _view.snapshot()}

func restore(data: Dictionary) -> bool:
	if _n <= 0 or _last_world == null or not DeviceRegistry.plain(data) or not DeviceRegistry.fields(data, SNAPSHOT_FIELDS):
		return false
	if data.ticks_per_report_period != _n or data.round_id != _round_id or data.branch_id != _branch_id or not data.visual_states is Dictionary or not data.goal_pending is Array or not data.device_sidecars is Array:
		return false
	var states: Dictionary = SensingKernel.restore_visual_states(data.visual_states, _last_world)
	if not states.ok:
		return false
	var buffer := ReportBuffer.new(_n)
	if not buffer.restore(data.device_buffer):
		return false
	var goals: Array[Dictionary] = []
	for raw: Variant in data.goal_pending:
		if not raw is Dictionary:
			return false
		var goal: GoalOperationRecord = GoalOperationRecord.from_data(raw)
		if goal == null or goal.round_id != _round_id or goal.branch_id != _branch_id or goal.report_cycle_id != goal.event_tick / _n + 1 or goal.report_cycle_id <= data.device_buffer.last_sealed_period_id:
			return false
		goals.append(goal.to_data())
	var sidecars: Array[Dictionary] = []
	for raw: Variant in data.device_sidecars:
		if not raw is Dictionary or not DeviceRegistry.fields(raw, ["record_type", "data", "device_configuration"]):
			return false
		var record: Variant = ObservationRecord.from_data(raw.data) if raw.record_type == "visual" else (PlateActivationRecord.from_data(raw.data) if raw.record_type == "plate_activation" else null)
		if record == null or record.round_id != _round_id or record.branch_id != _branch_id or record.report_cycle_id != (record.sense_tick if raw.record_type == "visual" else record.event_tick) / _n + 1 or not UnifiedReportBatch.public_device_configuration_valid(raw.device_configuration, record.device_id, raw.record_type):
			return false
		sidecars.append(raw.duplicate(true))
	var view := SystemAgentView.new()
	if not view.restore(data.system_view) or sidecars.size() != data.device_buffer.pending.size():
		return false
	for index: int in sidecars.size():
		if sidecars[index].record_type != data.device_buffer.pending[index].record_type or sidecars[index].data != data.device_buffer.pending[index].data:
			return false
	_device_buffer = buffer
	_goal_pending = goals
	_device_sidecars = sidecars
	_visual_states = states.states
	_view = view
	_clear_prepared()
	_staged.clear()
	return true

func _sidecars_for(step: SensingStepResult, world: WorldState) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for record: ObservationRecord in step.visual_records:
		var config: Dictionary = SystemAgentView.public_device_configuration(world.registry.get_entity(record.device_id))
		if not UnifiedReportBatch.public_device_configuration_valid(config, record.device_id, "visual"):
			return []
		result.append({"record_type": "visual", "data": record.to_data(), "device_configuration": config})
	for record: PlateActivationRecord in step.plate_records:
		var config: Dictionary = SystemAgentView.public_device_configuration(world.registry.get_entity(record.device_id))
		if not UnifiedReportBatch.public_device_configuration_valid(config, record.device_id, "plate_activation"):
			return []
		result.append({"record_type": "plate_activation", "data": record.to_data(), "device_configuration": config})
	return result

func _step_data(step: SensingStepResult) -> Dictionary:
	var visuals: Array = []
	var plates: Array = []
	for record: ObservationRecord in step.visual_records:
		if record == null:
			return {}
		visuals.append(record.to_data())
	for record: PlateActivationRecord in step.plate_records:
		if record == null:
			return {}
		plates.append(record.to_data())
	return {"states": step.next_visual_states.duplicate(true), "visuals": visuals, "plates": plates, "errors": step.errors.duplicate(true)}

func _entry_tick(entry: Dictionary) -> int:
	return entry.data.sense_tick if entry.record_type == "visual" else entry.data.event_tick

func _entry_id(entry: Dictionary) -> int:
	return entry.data.goal_id if entry.record_type == "goal_operation" else entry.data.device_id

func _entry_less(a: Dictionary, b: Dictionary) -> bool:
	var left: Array = [_entry_tick(a), _entry_id(a), a.record_type]
	var right: Array = [_entry_tick(b), _entry_id(b), b.record_type]
	for index: int in left.size():
		if left[index] == right[index]:
			continue
		return left[index] < right[index]
	return false

func _sort_entries(entries: Array[Dictionary]) -> void:
	for index: int in range(1, entries.size()):
		var item: Dictionary = entries[index]
		var prior: int = index - 1
		while prior >= 0 and _entry_less(item, entries[prior]):
			entries[prior + 1] = entries[prior]
			prior -= 1
		entries[prior + 1] = item

func _clear_prepared() -> void:
	_prepared = null
	_prepared_context.clear()
	_prepared_world.clear()

func _error(code: String) -> SensingStepResult:
	var result := SensingStepResult.new()
	result.errors.append({"code": code})
	return result
