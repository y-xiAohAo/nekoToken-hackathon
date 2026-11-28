extends RefCounted
class_name ObservationRecord
## A detached visual observation. Encoding never exposes a world position.

const FIELDS: Array[String] = ["round_id", "branch_id", "guess_cycle_id", "report_cycle_id", "device_id", "sense_tick", "result", "reliable_cells", "player_cell", "reason"]
const RESULTS: Array[String] = ["DETECTED", "NOT_DETECTED", "UNDETERMINED"]

var round_id: int
var branch_id: int
var guess_cycle_id: int
var report_cycle_id: int
var device_id: int
var sense_tick: int
var result: String
var reliable_cells: Array[Vector2i] = []
var player_cell: Variant = null
var reason: String = ""

static func make(data: Dictionary) -> ObservationRecord:
	if not DeviceRegistry.fields(data, FIELDS):
		return null
	for key: String in FIELDS.slice(0, 5):
		if typeof(data[key]) != TYPE_INT or data[key] < 1:
			return null
	if typeof(data.sense_tick) != TYPE_INT or data.sense_tick < 0 or typeof(data.result) != TYPE_STRING or data.result not in RESULTS or typeof(data.reason) != TYPE_STRING:
		return null
	if not data.reliable_cells is Array or (data.player_cell != null and not data.player_cell is Vector2i):
		return null
	var cells: Array[Vector2i] = []
	for cell: Variant in data.reliable_cells:
		if not cell is Vector2i or cell in cells:
			return null
		if not cells.is_empty() and (cell.y < cells[-1].y or (cell.y == cells[-1].y and cell.x <= cells[-1].x)):
			return null
		cells.append(cell)
	if data.result == "DETECTED" and (cells.is_empty() or data.player_cell not in cells or not data.reason.is_empty()):
		return null
	if data.result == "NOT_DETECTED" and (cells.is_empty() or data.player_cell != null or not data.reason.is_empty()):
		return null
	if data.result == "UNDETERMINED" and (not cells.is_empty() or data.player_cell != null or data.reason.is_empty()):
		return null
	var record := ObservationRecord.new()
	for key: String in FIELDS:
		record.set(key, data[key])
	record.reliable_cells = cells.duplicate()
	return record

static func from_data(data: Dictionary) -> ObservationRecord:
	if not DeviceRegistry.plain(data) or not DeviceRegistry.fields(data, FIELDS) or not data.reliable_cells is Array:
		return null
	var decoded: Dictionary = data.duplicate(true)
	var cells: Array[Vector2i] = []
	for item: Variant in data.reliable_cells:
		if not DeviceRegistry.cell(item):
			return null
		cells.append(DeviceRegistry.grid(item))
	decoded.reliable_cells = cells
	if data.player_cell != null:
		if not DeviceRegistry.cell(data.player_cell):
			return null
		decoded.player_cell = DeviceRegistry.grid(data.player_cell)
	return make(decoded)

func to_data() -> Dictionary:
	var cells: Array = []
	for cell: Vector2i in reliable_cells:
		cells.append([cell.x, cell.y])
	return {"round_id": round_id, "branch_id": branch_id, "guess_cycle_id": guess_cycle_id,
		"report_cycle_id": report_cycle_id, "device_id": device_id, "sense_tick": sense_tick,
		"result": result, "reliable_cells": cells,
		"player_cell": [player_cell.x, player_cell.y] if player_cell is Vector2i else null, "reason": reason}

func snapshot_copy() -> ObservationRecord:
	return from_data(to_data())
