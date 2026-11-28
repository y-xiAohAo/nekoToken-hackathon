extends RefCounted
class_name UnifiedReportBatch
## One complete, role-safe half-open reporting window.

const FIELDS: Array[String] = ["round_id", "branch_id", "guess_cycle_id", "report_period_id", "start_tick", "end_tick", "records"]
const CAMERA_PARAMETERS: Array[String] = ["enabled", "view_radius", "fov_angle", "scan_center", "scan_half_angle", "scan_speed"]
const ROBOT_PARAMETERS: Array[String] = ["view_radius", "move_speed"]

var round_id: int
var branch_id: int
var guess_cycle_id: int
var report_period_id: int
var start_tick: int
var end_tick: int
var records: Array[Dictionary] = []

static func from_data(data: Dictionary) -> UnifiedReportBatch:
	if not DeviceRegistry.plain(data) or not DeviceRegistry.fields(data, FIELDS) or not data.records is Array:
		return null
	for field: String in FIELDS.slice(0, 4):
		if typeof(data[field]) != TYPE_INT or data[field] < 1:
			return null
	if typeof(data.start_tick) != TYPE_INT or typeof(data.end_tick) != TYPE_INT or data.start_tick < 0 or data.end_tick <= data.start_tick:
		return null
	var n: int = data.end_tick - data.start_tick
	if data.start_tick % n != 0 or data.report_period_id != data.start_tick / n + 1:
		return null
	var previous_order: Array = []
	var visual_keys: Dictionary = {}
	for entry: Variant in data.records:
		if not entry is Dictionary or not entry.has("record_type") or not entry.has("data") or not entry.data is Dictionary:
			return null
		var record: Variant = null
		var event_tick: int = -1
		var entity_id: int = -1
		if entry.record_type == "visual":
			if not DeviceRegistry.fields(entry, ["record_type", "data", "device_configuration"]):
				return null
			record = ObservationRecord.from_data(entry.data)
		elif entry.record_type == "plate_activation":
			if not DeviceRegistry.fields(entry, ["record_type", "data", "device_configuration"]):
				return null
			record = PlateActivationRecord.from_data(entry.data)
		elif entry.record_type == "goal_operation":
			if not DeviceRegistry.fields(entry, ["record_type", "data"]):
				return null
			record = GoalOperationRecord.from_data(entry.data)
		else:
			return null
		if record == null:
			return null
		if entry.record_type == "goal_operation":
			event_tick = record.event_tick
			entity_id = record.goal_id
		else:
			event_tick = record.sense_tick if entry.record_type == "visual" else record.event_tick
			entity_id = record.device_id
			if not public_device_configuration_valid(entry.device_configuration, entity_id, entry.record_type):
				return null
			if entry.record_type == "plate_activation" and entry.data.cell != entry.device_configuration.cell:
				return null
			if entry.record_type == "visual":
				var key: String = "%d:%d:%d:%d" % [record.round_id, record.branch_id, record.device_id, event_tick]
				if visual_keys.has(key):
					return null
				visual_keys[key] = true
		if event_tick < data.start_tick or event_tick >= data.end_tick or record.report_cycle_id != data.report_period_id or record.round_id != data.round_id or record.branch_id != data.branch_id:
			return null
		var order: Array = [event_tick, entity_id, entry.record_type]
		if not previous_order.is_empty() and _less(order, previous_order):
			return null
		previous_order = order
	var batch := UnifiedReportBatch.new()
	for field: String in FIELDS:
		if field != "records":
			batch.set(field, data[field])
	batch.records.assign(data.records.duplicate(true))
	return batch

static func public_device_configuration_valid(value: Variant, entity_id: int, record_type: String = "") -> bool:
	if not value is Dictionary or not DeviceRegistry.plain(value) or value.get("id") != entity_id:
		return false
	match value.get("kind"):
		"camera":
			if record_type == "plate_activation" or not DeviceRegistry.fields(value, ["id", "kind", "cell", "parameters", "heading", "scan_direction"]) or not DeviceRegistry.cell(value.cell) or not DeviceRegistry.fields(value.parameters, CAMERA_PARAMETERS) or not DeviceRegistry.number(value.heading) or typeof(value.scan_direction) != TYPE_INT or value.scan_direction not in [-1, 1]:
				return false
			if typeof(value.parameters.enabled) != TYPE_BOOL:
				return false
			for key: String in CAMERA_PARAMETERS:
				if key != "enabled" and not DeviceRegistry.number(value.parameters[key]):
					return false
			return value.parameters.view_radius > 0 and value.parameters.fov_angle > 0 and value.parameters.fov_angle <= TAU
		"robot":
			if record_type == "plate_activation" or not DeviceRegistry.fields(value, ["id", "kind", "patrol_path", "parameters"]) or not value.patrol_path is Array or value.patrol_path.is_empty() or not DeviceRegistry.fields(value.parameters, ROBOT_PARAMETERS):
				return false
			for cell: Variant in value.patrol_path:
				if not DeviceRegistry.cell(cell):
					return false
			return DeviceRegistry.number(value.parameters.view_radius) and value.parameters.view_radius > 0 and DeviceRegistry.number(value.parameters.move_speed) and value.parameters.move_speed > 0
		"pressure_plate":
			return record_type != "visual" and DeviceRegistry.fields(value, ["id", "kind", "cell"]) and DeviceRegistry.cell(value.cell)
	return false

static func _less(a: Array, b: Array) -> bool:
	for index: int in a.size():
		if a[index] == b[index]:
			continue
		return a[index] < b[index]
	return false

func to_data() -> Dictionary:
	return {"round_id": round_id, "branch_id": branch_id, "guess_cycle_id": guess_cycle_id,
		"report_period_id": report_period_id, "start_tick": start_tick, "end_tick": end_tick,
		"records": records.duplicate(true)}

func snapshot_copy() -> UnifiedReportBatch:
	return from_data(to_data())
