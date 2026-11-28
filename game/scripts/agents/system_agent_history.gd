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


static func from_snapshot(data: Dictionary) -> SystemAgentHistory:
	if not DeviceRegistry.plain(data) or not DeviceRegistry.fields(data, ["entries"]) or not data.entries is Array:
		return null
	var history := SystemAgentHistory.new()
	for entry: Variant in data.entries:
		if not entry is Dictionary:
			return null
		var accepted: bool = false
		match entry.get("kind"):
			"guess":
				accepted = history.append_guess(entry)
			"dispatch":
				accepted = history.append_dispatch(entry)
			"archived_report":
				if DeviceRegistry.fields(entry, ["kind", "reason", "batch"]):
					accepted = history.append_archived_batches([entry.batch], entry.reason)
			"round_setup":
				accepted = history.append_round_setup(entry)
		if not accepted:
			return null
	return history


func append_archived_batches(batches: Array[Dictionary], reason: String) -> bool:
	if reason not in ["abandoned_branch", "previous_round"] or not DeviceRegistry.plain(batches):
		return false
	var candidate: Array[Dictionary] = _entries.duplicate(true)
	var identities: Dictionary = {}
	for existing: Dictionary in candidate:
		if existing.kind == "archived_report":
			var batch: Dictionary = existing.batch
			identities["%d:%d:%d" % [batch.round_id, batch.branch_id, batch.report_period_id]] = true
	var additions: Array[Dictionary] = []
	for raw: Dictionary in batches:
		var batch: UnifiedReportBatch = UnifiedReportBatch.from_data(raw)
		if batch == null:
			return false
		var identity: String = "%d:%d:%d" % [batch.round_id, batch.branch_id, batch.report_period_id]
		if identities.has(identity):
			continue
		identities[identity] = true
		additions.append({"kind": "archived_report", "reason": reason, "batch": batch.to_data()})
	candidate.append_array(additions)
	_entries = candidate
	return true


func append_round_setup(entry: Dictionary) -> bool:
	if not DeviceRegistry.plain(entry) or not DeviceRegistry.fields(entry, ["kind", "context", "mode", "commands", "status", "revision_before", "revision_after", "errors"]):
		return false
	if entry.kind != "round_setup" or not AgentProtocol._system_context(entry.context) or entry.mode not in ["APPLY", "KEEP_CURRENT"] or entry.status not in ["APPLIED", "UNCHANGED", "REJECTED"]:
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
