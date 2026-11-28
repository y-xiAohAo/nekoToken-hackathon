extends RefCounted
class_name GoalOperationRecord
## Trusted, position-free goal event for the unified report.

const FIELDS: Array[String] = ["round_id", "branch_id", "guess_cycle_id", "report_cycle_id", "goal_id", "event_tick", "type"]
const TYPES: Array[String] = ["GOAL_OPERATION_STARTED", "GOAL_OPERATION_CANCELLED", "GOAL_OPERATION_COMPLETED"]

var round_id: int
var branch_id: int
var guess_cycle_id: int
var report_cycle_id: int
var goal_id: int
var event_tick: int
var type: String

static func from_data(data: Dictionary) -> GoalOperationRecord:
	if not DeviceRegistry.plain(data) or not DeviceRegistry.fields(data, FIELDS):
		return null
	for field: String in FIELDS.slice(0, 5):
		if typeof(data[field]) != TYPE_INT or data[field] < 1:
			return null
	if typeof(data.event_tick) != TYPE_INT or data.event_tick < 0 or typeof(data.type) != TYPE_STRING or data.type not in TYPES:
		return null
	var record := GoalOperationRecord.new()
	for field: String in FIELDS:
		record.set(field, data[field])
	return record

func to_data() -> Dictionary:
	return {"round_id": round_id, "branch_id": branch_id, "guess_cycle_id": guess_cycle_id,
		"report_cycle_id": report_cycle_id, "goal_id": goal_id, "event_tick": event_tick, "type": type}

func snapshot_copy() -> GoalOperationRecord:
	return from_data(to_data())
