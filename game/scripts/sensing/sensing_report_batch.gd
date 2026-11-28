extends RefCounted
class_name SensingReportBatch
## One sealed half-open device-only report interval.

const FIELDS: Array[String] = ["round_id", "branch_id", "guess_cycle_id", "report_period_id", "start_tick", "end_tick", "records"]

var round_id: int
var branch_id: int
var guess_cycle_id: int
var report_period_id: int
var start_tick: int
var end_tick: int
var records: Array[Dictionary] = []

static func from_data(data: Dictionary) -> SensingReportBatch:
	if not DeviceRegistry.plain(data) or not DeviceRegistry.fields(data, FIELDS) or not data.records is Array:
		return null
	for key: String in FIELDS.slice(0, 4):
		if typeof(data[key]) != TYPE_INT or data[key] < 1:
			return null
	if typeof(data.start_tick) != TYPE_INT or typeof(data.end_tick) != TYPE_INT or data.start_tick < 0 or data.end_tick <= data.start_tick:
		return null
	var n: int = data.end_tick - data.start_tick
	if data.start_tick % n != 0 or data.report_period_id != data.start_tick / n + 1:
		return null
	var previous_key: Array = []
	for index: int in data.records.size():
		var entry: Variant = data.records[index]
		if not DeviceRegistry.fields(entry, ["record_type", "data"], ["origin_branch_id"]) or not entry.data is Dictionary:
			return null
		var record: Variant = null
		if entry.record_type == "visual":
			record = ObservationRecord.from_data(entry.data)
		elif entry.record_type == "plate_activation":
			record = PlateActivationRecord.from_data(entry.data)
		else:
			return null
		if record == null:
			return null
		if entry.has("origin_branch_id") and (typeof(entry.origin_branch_id) != TYPE_INT or entry.origin_branch_id < 1 or entry.origin_branch_id == record.branch_id):
			return null
		var tick: int = record.sense_tick if entry.record_type == "visual" else record.event_tick
		if tick < data.start_tick or tick >= data.end_tick or record.report_cycle_id != data.report_period_id or record.round_id != data.round_id or record.branch_id != data.branch_id:
			return null
		var order: Array = [tick, record.device_id, entry.record_type]
		if not previous_key.is_empty() and _less(order, previous_key):
			return null
		previous_key = order
	var batch := SensingReportBatch.new()
	for key: String in FIELDS:
		if key != "records":
			batch.set(key, data[key])
	batch.records.assign(data.records.duplicate(true))
	return batch

static func _less(a: Array, b: Array) -> bool:
	for i: int in a.size():
		if a[i] == b[i]:
			continue
		return a[i] < b[i]
	return false

func to_data() -> Dictionary:
	return {"round_id": round_id, "branch_id": branch_id, "guess_cycle_id": guess_cycle_id,
		"report_period_id": report_period_id, "start_tick": start_tick, "end_tick": end_tick,
		"records": records.duplicate(true)}

func snapshot_copy() -> SensingReportBatch:
	return from_data(to_data())
