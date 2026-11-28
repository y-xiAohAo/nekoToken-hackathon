extends RefCounted
class_name Module6ReportsTests
## Branch provenance and delivered-only system memory contracts.

var passed: int = 0
var failed: int = 0


func run() -> Dictionary:
	_check(_ancestor_prefix_and_child_suffix(), "published ancestor prefix keeps source identity")
	_check(_rejects_unregistered_mixed_branch(), "lineage rejects arbitrary report mixing")
	_check(_fork_tick_pending_once(), "fork tick pending records keep origin and deliver once")
	_check(_archive_delivered_only(), "archived delivered reports are deduplicated and safe")
	_check(_history_rejects_hidden_fields(), "system history rejects hidden fields")
	return {"passed": passed, "failed": failed}


func _check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		push_error("MODULE 6 REPORTS TEST FAILED: " + label)


func _world() -> WorldState:
	return LevelTemplate.from_data(PrototypeConfig.level_data()).instantiate_world()


func _empty_batch(branch_id: int, period: int, guess_cycle_id: int = 1) -> UnifiedReportBatch:
	return UnifiedReportBatch.from_data({"round_id": 1, "branch_id": branch_id,
		"guess_cycle_id": guess_cycle_id, "report_period_id": period,
		"start_tick": (period - 1) * 30, "end_tick": period * 30,
		"records": []})


func _lineage() -> Array[Dictionary]:
	return [{"round_id": 1, "branch_id": 1, "parent_branch_id": 0,
		"fork_tick": 0, "fork_report_period_id": 0},
		{"round_id": 1, "branch_id": 2, "parent_branch_id": 1,
			"fork_tick": 60, "fork_report_period_id": 2}]


func _ancestor_prefix_and_child_suffix() -> bool:
	var view := SystemAgentView.new()
	if not view.initialize(_world(), PrototypeConfig.system_dispatch_policy()):
		return false
	if not view.append_batch(_empty_batch(1, 1)) or not view.append_batch(_empty_batch(1, 2)):
		return false
	var before: Array = view.to_data().reports
	if not view.set_branch_lineage(_lineage()) or not view.append_batch(_empty_batch(2, 3, 2)):
		return false
	var result: Dictionary = view.to_data()
	return result.view_schema_version == 2 and result.branch_lineage == _lineage() \
		and result.reports.slice(0, 2) == before and result.reports[2].branch_id == 2 \
		and result.reports[0].branch_id == 1


func _rejects_unregistered_mixed_branch() -> bool:
	var view := SystemAgentView.new()
	if not view.initialize(_world()) or not view.append_batch(_empty_batch(1, 1)):
		return false
	var wrong: Array[Dictionary] = _lineage()
	wrong[1].fork_report_period_id = 2
	wrong[1].fork_tick = 60
	if view.set_branch_lineage(wrong):
		return false
	var good: Array[Dictionary] = [{"round_id": 1, "branch_id": 1, "parent_branch_id": 0,
		"fork_tick": 0, "fork_report_period_id": 0},
		{"round_id": 1, "branch_id": 2, "parent_branch_id": 1,
			"fork_tick": 30, "fork_report_period_id": 1}]
	if not view.set_branch_lineage(good):
		return false
	return not view.append_batch(_empty_batch(3, 2)) and view.to_data().reports.size() == 1


func _fork_tick_pending_once() -> bool:
	var world: WorldState = _world()
	var sensing := RuntimeSensingCoordinator.new()
	if world == null or not sensing.initialize_round(world, {"round_id": 1, "branch_id": 1,
		"guess_cycle_id": 1, "report_cycle_id": 1, "sense_tick": 0}, 30):
		return false
	var original: Dictionary = sensing.snapshot()
	if original.device_buffer.pending.is_empty():
		return false
	var path: Array[Dictionary] = [{"round_id": 1, "branch_id": 1, "parent_branch_id": 0,
		"fork_tick": 0, "fork_report_period_id": 0},
		{"round_id": 1, "branch_id": 2, "parent_branch_id": 1,
			"fork_tick": 0, "fork_report_period_id": 0}]
	var forked: RuntimeSensingCoordinator = RuntimeSensingCoordinator.from_cycle_checkpoint(original, world, 2, path, 0)
	if forked == null:
		return false
	var pending: Dictionary = forked.snapshot()
	if pending.device_buffer.pending.size() != original.device_buffer.pending.size():
		return false
	for entry: Dictionary in pending.device_buffer.pending:
		if entry.origin_branch_id != 1 or entry.data.branch_id != 2 or entry.data.sense_tick != 0:
			return false
	var boundary := ReportBoundary.new(1, 2, 1, 1, 0, 30, false)
	if not forked.seal_report_batch(boundary) or not forked.update_system_view(boundary, world) or not forked.finish_report_boundary():
		return false
	var delivered: Dictionary = forked.get_system_view()
	if delivered.reports.size() != 1 or delivered.reports[0].records.size() != original.device_buffer.pending.size():
		return false
	for entry: Dictionary in delivered.reports[0].records:
		if entry.origin_branch_id != 1 or entry.data.branch_id != 2:
			return false
	return forked.snapshot().device_buffer.pending.is_empty()


func _archive_delivered_only() -> bool:
	var history := SystemAgentHistory.new()
	var batch: Dictionary = _empty_batch(1, 1).to_data()
	if not history.append_archived_batches([batch], "abandoned_branch"):
		return false
	if not history.append_archived_batches([batch], "abandoned_branch"):
		return false
	var before: Dictionary = history.snapshot()
	var malformed: Dictionary = batch.duplicate(true)
	malformed["player_position"] = [1, 2]
	return before.entries.size() == 1 and before.entries[0].batch == batch \
		and not history.append_archived_batches([malformed], "previous_round") \
		and history.snapshot() == before \
		and SystemAgentHistory.from_snapshot(before) != null


func _history_rejects_hidden_fields() -> bool:
	var history := SystemAgentHistory.new()
	var entry: Dictionary = {"kind": "round_setup", "context": AgentProtocol.make_request_context(AgentProtocol.SYSTEM_AGENT, 9, 2, 3, 1),
		"mode": "KEEP_CURRENT", "commands": [], "status": "UNCHANGED",
		"revision_before": 0, "revision_after": 0, "errors": []}
	if not history.append_round_setup(entry):
		return false
	var injected: Dictionary = entry.duplicate(true)
	injected["player_position"] = [1, 2]
	return not history.append_round_setup(injected) and history.snapshot().entries.size() == 1
