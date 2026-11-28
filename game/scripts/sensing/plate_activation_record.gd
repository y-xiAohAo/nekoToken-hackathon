extends RefCounted
class_name PlateActivationRecord
## Anonymous entry event; actor identity is intentionally absent.

const FIELDS: Array[String] = ["round_id", "branch_id", "guess_cycle_id", "report_cycle_id", "device_id", "event_tick", "cell"]

var round_id: int
var branch_id: int
var guess_cycle_id: int
var report_cycle_id: int
var device_id: int
var event_tick: int
var cell: Vector2i

static func make(data: Dictionary) -> PlateActivationRecord:
	if not DeviceRegistry.fields(data, FIELDS):
		return null
	for key: String in FIELDS.slice(0, 5):
		if typeof(data[key]) != TYPE_INT or data[key] < 1:
			return null
	if typeof(data.event_tick) != TYPE_INT or data.event_tick < 0 or not data.cell is Vector2i:
		return null
	var record := PlateActivationRecord.new()
	for key: String in FIELDS:
		record.set(key, data[key])
	return record

static func from_data(data: Dictionary) -> PlateActivationRecord:
	if not DeviceRegistry.plain(data) or not DeviceRegistry.fields(data, FIELDS) or not DeviceRegistry.cell(data.cell):
		return null
	var decoded: Dictionary = data.duplicate(true)
	decoded.cell = DeviceRegistry.grid(data.cell)
	return make(decoded)

func to_data() -> Dictionary:
	return {"round_id": round_id, "branch_id": branch_id, "guess_cycle_id": guess_cycle_id,
		"report_cycle_id": report_cycle_id, "device_id": device_id, "event_tick": event_tick,
		"cell": [cell.x, cell.y]}

func snapshot_copy() -> PlateActivationRecord:
	return from_data(to_data())
