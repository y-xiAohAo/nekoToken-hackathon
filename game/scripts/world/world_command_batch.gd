extends RefCounted
class_name WorldCommandBatch

var _data: Dictionary = {}


static func from_data(data: Dictionary) -> WorldCommandBatch:
	if not DeviceRegistry.plain(data) or not DeviceRegistry.fields(data, ["context", "source", "base_world_revision", "mode", "commands"]):
		return null
	if not DeviceRegistry.fields(data.context, AgentProtocol.CONTEXT_FIELDS) or not AgentProtocol.contexts_match(data.context, data.context):
		return null
	if data.source not in ["contact", "dispatch"] or data.mode not in ["APPLY", "KEEP_CURRENT"]:
		return null
	if typeof(data.base_world_revision) != TYPE_INT or data.base_world_revision < 0 or not data.commands is Array:
		return null
	if (data.mode == "KEEP_CURRENT") != data.commands.is_empty():
		return null
	for command: Variant in data.commands:
		if not command_valid(command):
			return null
	var result := WorldCommandBatch.new()
	result._data = data.duplicate(true)
	return result


func to_data() -> Dictionary:
	return _data.duplicate(true)


static func command_valid(command: Variant) -> bool:
	if not command is Dictionary or not command.has("type"):
		return false
	match command.type:
		"SetMapCell":
			return DeviceRegistry.fields(command, ["type", "cell", "cell_kind"]) and DeviceRegistry.cell(command.cell) and command.cell_kind in ["FLOOR", "WALL"]
		"AddDevice":
			return DeviceRegistry.fields(command, ["type", "device"]) and command.device is Dictionary
		"RemoveDevice":
			return DeviceRegistry.fields(command, ["type", "id"]) and _id(command.id)
		"MoveDevice":
			return DeviceRegistry.fields(command, ["type", "id", "cell"], ["mount_type", "wall_side"]) and _id(command.id) and DeviceRegistry.cell(command.cell)
		"SetDeviceParameter":
			return DeviceRegistry.fields(command, ["type", "id", "parameter", "value"]) and _id(command.id) and command.parameter is String
		"SetPatrolPath":
			if not DeviceRegistry.fields(command, ["type", "robot_id", "cells"]) or not _id(command.robot_id) or not command.cells is Array:
				return false
			for cell: Variant in command.cells:
				if not DeviceRegistry.cell(cell):
					return false
			return true
	return false


static func _id(value: Variant) -> bool:
	return typeof(value) == TYPE_INT and value > 0
