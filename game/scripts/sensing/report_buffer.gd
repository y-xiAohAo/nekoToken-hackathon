extends RefCounted
class_name ReportBuffer
## Validated pending device records, never a complete gameplay report.

var _n: int
var _last_sealed_period_id: int = 0
var _pending: Array[Dictionary] = []

func _init(ticks_per_report_period: int) -> void:
	_n = ticks_per_report_period

func append_visual(record: ObservationRecord) -> bool:
	if record == null:
		return false
	var records: Array[ObservationRecord] = [record]
	return append_all(records, [])

func append_plate(record: PlateActivationRecord) -> bool:
	if record == null:
		return false
	var records: Array[PlateActivationRecord] = [record]
	return append_all([], records)

func append_all(visual_records: Array[ObservationRecord], plate_records: Array[PlateActivationRecord]) -> bool:
	if _n <= 0:
		return false
	var incoming: Array[Dictionary] = []
	for record: ObservationRecord in visual_records:
		if record == null or ObservationRecord.from_data(record.to_data()) == null or not _period_valid(record.sense_tick, record.report_cycle_id):
			return false
		var entry: Dictionary = {"record_type": "visual", "data": record.to_data()}
		if _duplicate_visual(_pending, entry) or _duplicate_visual(incoming, entry):
			return false
		incoming.append(entry)
	for record: PlateActivationRecord in plate_records:
		if record == null or PlateActivationRecord.from_data(record.to_data()) == null or not _period_valid(record.event_tick, record.report_cycle_id):
			return false
		incoming.append({"record_type": "plate_activation", "data": record.to_data()})
	for entry: Dictionary in incoming:
		_pending.append(entry.duplicate(true))
	return true

func seal(boundary: ReportBoundary) -> SensingReportBatch:
	if boundary == null or _n <= 0 or boundary.start_tick < 0 or boundary.end_tick - boundary.start_tick != _n or boundary.start_tick % _n != 0:
		return null
	if boundary.report_period_id != boundary.start_tick / _n + 1 or boundary.report_period_id != _last_sealed_period_id + 1:
		return null
	if boundary.round_id < 1 or boundary.branch_id < 1 or boundary.guess_cycle_id < 1:
		return null
	var chosen: Array[Dictionary] = []
	var remaining: Array[Dictionary] = []
	for entry: Dictionary in _pending:
		var data: Dictionary = entry.data
		var tick: int = data.sense_tick if entry.record_type == "visual" else data.event_tick
		if tick >= boundary.start_tick and tick < boundary.end_tick:
			if data.report_cycle_id != boundary.report_period_id or data.round_id != boundary.round_id or data.branch_id != boundary.branch_id:
				return null
			chosen.append(entry.duplicate(true))
		else:
			if tick < boundary.start_tick:
				return null
			remaining.append(entry.duplicate(true))
	# Insertion sort preserves original order for equal event keys.
	for index: int in range(1, chosen.size()):
		var item: Dictionary = chosen[index]
		var prior: int = index - 1
		while prior >= 0 and _entry_less(item, chosen[prior]):
			chosen[prior + 1] = chosen[prior]
			prior -= 1
		chosen[prior + 1] = item
	var batch: SensingReportBatch = SensingReportBatch.from_data({"round_id": boundary.round_id, "branch_id": boundary.branch_id,
		"guess_cycle_id": boundary.guess_cycle_id, "report_period_id": boundary.report_period_id,
		"start_tick": boundary.start_tick, "end_tick": boundary.end_tick, "records": chosen})
	if batch == null:
		return null
	_pending = remaining
	_last_sealed_period_id = boundary.report_period_id
	return batch

func snapshot() -> Dictionary:
	return {"ticks_per_report_period": _n, "last_sealed_period_id": _last_sealed_period_id, "pending": _pending.duplicate(true)}

func restore(data: Dictionary) -> bool:
	if not DeviceRegistry.plain(data) or not DeviceRegistry.fields(data, ["ticks_per_report_period", "last_sealed_period_id", "pending"]):
		return false
	if typeof(data.ticks_per_report_period) != TYPE_INT or data.ticks_per_report_period != _n or _n <= 0 or typeof(data.last_sealed_period_id) != TYPE_INT or data.last_sealed_period_id < 0 or not data.pending is Array:
		return false
	var candidate: Array[Dictionary] = []
	for entry: Variant in data.pending:
		if not DeviceRegistry.fields(entry, ["record_type", "data"]) or not entry.data is Dictionary:
			return false
		var record: Variant = ObservationRecord.from_data(entry.data) if entry.record_type == "visual" else (PlateActivationRecord.from_data(entry.data) if entry.record_type == "plate_activation" else null)
		if record == null:
			return false
		var tick: int = record.sense_tick if entry.record_type == "visual" else record.event_tick
		if record.report_cycle_id != tick / _n + 1 or record.report_cycle_id <= data.last_sealed_period_id:
			return false
		if entry.record_type == "visual" and _duplicate_visual(candidate, entry):
			return false
		candidate.append(entry.duplicate(true))
	_pending = candidate
	_last_sealed_period_id = data.last_sealed_period_id
	return true

func pending_count() -> int:
	return _pending.size()

func _period_valid(event_tick: int, report_cycle_id: int) -> bool:
	return event_tick >= 0 and report_cycle_id == event_tick / _n + 1 and report_cycle_id > _last_sealed_period_id

func _duplicate_visual(entries: Array[Dictionary], candidate: Dictionary) -> bool:
	for entry: Dictionary in entries:
		if entry.record_type != "visual":
			continue
		var left: Dictionary = entry.data
		var right: Dictionary = candidate.data
		if left.round_id == right.round_id and left.branch_id == right.branch_id and left.device_id == right.device_id and left.sense_tick == right.sense_tick:
			return true
	return false

func _entry_less(a: Dictionary, b: Dictionary) -> bool:
	var a_tick: int = a.data.sense_tick if a.record_type == "visual" else a.data.event_tick
	var b_tick: int = b.data.sense_tick if b.record_type == "visual" else b.data.event_tick
	if a_tick != b_tick:
		return a_tick < b_tick
	if a.data.device_id != b.data.device_id:
		return a.data.device_id < b.data.device_id
	return a.record_type < b.record_type
