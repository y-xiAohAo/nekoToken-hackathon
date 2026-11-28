extends RefCounted
class_name SystemAgentHistory
## Persistent safe action history, separate from restorable sensing reports.

var _entries: Array[Dictionary] = []

func append_guess(entry: Dictionary) -> bool:
	if not DeviceRegistry.plain(entry) or not DeviceRegistry.fields(entry, ["kind", "context", "as_of", "origin_cell", "size", "verdict"]):
		return false
	if entry.kind != "guess" or not AgentProtocol._system_context(entry.context) or not AgentProtocol._as_of_valid(entry.as_of):
		return false
	if not DeviceRegistry.cell(entry.origin_cell) or not DeviceRegistry.cell(entry.size) or entry.size[0] <= 0 or entry.size[1] <= 0 or entry.verdict not in ["HIT", "MISS"]:
		return false
	_entries.append(entry.duplicate(true))
	return true

func append_dispatch(entry: Dictionary) -> bool:
	if not DeviceRegistry.plain(entry) or not DeviceRegistry.fields(entry, ["kind", "context", "mode", "commands", "status", "revision_before", "revision_after", "errors"]):
		return false
	if entry.kind != "dispatch" or not AgentProtocol._system_context(entry.context) or entry.mode not in ["APPLY", "KEEP_CURRENT"] or entry.status not in ["APPLIED", "UNCHANGED", "REJECTED"]:
		return false
	if not entry.commands is Array or not entry.errors is Array or typeof(entry.revision_before) != TYPE_INT or typeof(entry.revision_after) != TYPE_INT or entry.revision_before < 0 or entry.revision_after < entry.revision_before:
		return false
	for command: Variant in entry.commands:
		if not WorldCommandBatch.command_valid(command):
			return false
	for error: Variant in entry.errors:
		if not DeviceRegistry.fields(error, ["code", "command_index"]) or not error.code is String or typeof(error.command_index) != TYPE_INT:
			return false
	_entries.append(entry.duplicate(true))
	return true

func snapshot() -> Dictionary:
	return {"entries": _entries.duplicate(true)}
