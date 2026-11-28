extends RefCounted
class_name ResetCoordinator
## Trusted cycle checkpoints and atomic local RESET orchestration.

var _service: WorldCommandService
var _session: GameSession
var _sensing: RuntimeSensingCoordinator
var _run: RunState
var _history: SystemAgentHistory
var _contact: ContactSessionController
var _assistant_memory: PlayerAssistantMemoryPort
var _checkpoint: CycleCheckpoint
var _last_error: String = ""
var _round_fixture: Dictionary = {}


func _init(service: WorldCommandService, session: GameSession, sensing: RuntimeSensingCoordinator, run: RunState, history: SystemAgentHistory, contact: ContactSessionController = null, assistant_memory: PlayerAssistantMemoryPort = null, round_fixture: Dictionary = {}) -> void:
	_service = service
	_session = session
	_sensing = sensing
	_run = run
	_history = history
	_contact = contact
	_assistant_memory = assistant_memory if assistant_memory != null else PlayerAssistantMemoryPort.new()
	_round_fixture = (PrototypeConfig.round_setup_fixture() if round_fixture.is_empty() else round_fixture).duplicate(true)


func capture_initial_checkpoint() -> bool:
	_last_error = ""
	var state: Dictionary = _session.get_state_snapshot()
	var cycle: Dictionary = _session.get_cycle_snapshot()
	if state.phase != SessionPhase.Phase.ACTION or cycle.simulation_tick != 0 or state.guess_cycle_id != 1:
		return _reject("INVALID_PHASE")
	return _capture()


func complete_cycle_start() -> bool:
	_last_error = ""
	if _session.get_state_snapshot().phase != SessionPhase.Phase.CYCLE_START_PENDING:
		return _reject("INVALID_PHASE")
	if not _capture():
		return false
	if not _session.resume_cycle(true):
		_checkpoint = null
		return _reject("RESUME_REJECTED")
	return true


func choose_local_reset() -> bool:
	_last_error = ""
	if _checkpoint == null or _session.get_state_snapshot().phase != SessionPhase.Phase.RESET_CHOICE:
		return _reject("INVALID_PHASE")
	if _run.snapshot().remaining_local_resets <= 0:
		return decline_local_reset()
	var data: Dictionary = _checkpoint.to_data()
	var current_world: WorldState = _service.get_world_snapshot()
	var current_view: Dictionary = _sensing.get_system_view()
	var prefix: Array = data.sensing.system_view.reports
	if current_world == null or current_view.is_empty() or current_view.reports.size() < prefix.size():
		return _reject("INVALID_CHECKPOINT")
	for index: int in prefix.size():
		if current_view.reports[index] != prefix[index]:
			return _reject("REPORT_PREFIX_MISMATCH")
	var abandoned: Array[Dictionary] = []
	abandoned.assign(current_view.reports.slice(prefix.size()).duplicate(true))
	var candidate_history: SystemAgentHistory = SystemAgentHistory.from_snapshot(_history.snapshot())
	if candidate_history == null or not candidate_history.append_archived_batches(abandoned, "abandoned_branch"):
		return _reject("INVALID_HISTORY")
	var prepared_run: Dictionary = _run.prepare_local_fork(_checkpoint, current_world)
	if prepared_run.is_empty():
		return _reject("RESET_BUDGET")
	var prepared_session: Dictionary = _session.prepare_cycle_restore(data.session, data.cycle, prepared_run.branch_id)
	if prepared_session.is_empty():
		return _reject("INVALID_SESSION")
	var restored_world: WorldState = WorldState.from_snapshot(data.world)
	if restored_world == null:
		return _reject("INVALID_WORLD")
	var lineage: Array[Dictionary] = []
	for edge: Dictionary in prepared_run.branch_edges:
		if edge.round_id == prepared_run.round_id:
			lineage.append(edge.duplicate(true))
	var candidate_sensing: RuntimeSensingCoordinator = RuntimeSensingCoordinator.from_cycle_checkpoint(data.sensing, restored_world, prepared_run.branch_id, lineage, data.source.simulation_tick)
	if candidate_sensing == null:
		return _reject("INVALID_SENSING")
	var restored: Dictionary = _service.restore_trusted_snapshot(data.world, current_world.world_revision, prepared_run.next_entity_id, prepared_run.next_obstacle_id)
	if restored.get("ok") != true:
		return _reject(str(restored.get("errors", [{"code": "RESTORE_FAILED"}])[0].code))
	_history._entries.assign(candidate_history.snapshot().entries)
	_run.accept_prepared(prepared_run)
	_session.accept_cycle_restore(prepared_session)
	_sensing = candidate_sensing
	if _contact != null:
		_contact.invalidate_for_branch_change()
	var edge: Dictionary = prepared_run.branch_edges[-1]
	if not _assistant_memory.on_branch_change({"round_id": edge.round_id, "branch_id": edge.branch_id, "parent_branch_id": edge.parent_branch_id}):
		_last_error = "ASSISTANT_MEMORY_FAULT"
		return false
	return true


func decline_local_reset() -> bool:
	_last_error = ""
	if not _session.decline_local_reset():
		return _reject("INVALID_PHASE")
	return true


func advance_round() -> bool:
	_last_error = ""
	var state: Dictionary = _session.get_state_snapshot()
	if state.phase != SessionPhase.Phase.ROUND_END:
		return _reject("INVALID_PHASE")
	var prepared_run: Dictionary = _run.prepare_next_round(state.round_result)
	if prepared_run.is_empty():
		return _reject("ROUND_ALREADY_RECORDED")
	var candidate_history: SystemAgentHistory = SystemAgentHistory.from_snapshot(_history.snapshot())
	var old_reports: Array[Dictionary] = []
	old_reports.assign(_sensing.get_system_view().reports.duplicate(true))
	if candidate_history == null or not candidate_history.append_archived_batches(old_reports, "previous_round"):
		return _reject("INVALID_HISTORY")
	if not prepared_run.next_round:
		_history._entries.assign(candidate_history.snapshot().entries)
		_run.accept_prepared(prepared_run)
		return true
	var old_world: WorldState = _service.get_world_snapshot()
	var candidate_world: WorldState = LevelTemplate.from_data(PrototypeConfig.level_data()).instantiate_world()
	if old_world == null or candidate_world == null or candidate_world.template_key != old_world.template_key:
		return _reject("INVALID_WORLD")
	prepared_run.next_entity_id = maxi(prepared_run.next_entity_id, old_world.next_entity_id)
	prepared_run.next_obstacle_id = maxi(prepared_run.next_obstacle_id, old_world.next_obstacle_id)
	var setup: Dictionary = _session.begin_round_setup(prepared_run.branch_id)
	if setup.is_empty():
		return _reject("INVALID_SESSION")
	var view := SystemAgentView.new()
	if not view.initialize(candidate_world, PrototypeConfig.round_setup_policy()):
		return _reject("INVALID_VIEW")
	var view_data: Dictionary = view.to_data()
	view_data.history = candidate_history.snapshot().entries
	var request: Dictionary = AgentProtocol.make_round_setup_request(setup.context, view_data, PrototypeConfig.round_setup_policy())
	if request.is_empty():
		return _reject("INVALID_REQUEST")
	var parsed: Dictionary = AgentProtocol.parse_round_setup_response(SimulatedRoundSetupAgent.respond(request, _round_fixture), setup.context)
	if not parsed.ok:
		return _reject("INVALID_ROUND_SETUP_RESPONSE")
	var payload: Dictionary = parsed.payload
	var batch: WorldCommandBatch = WorldCommandBatch.from_data({"context": setup.context, "source": "round_setup",
		"base_world_revision": candidate_world.world_revision, "mode": payload.mode, "commands": payload.commands})
	if batch == null:
		return _reject("INVALID_ROUND_SETUP_RESPONSE")
	var temporary := WorldCommandService.new(candidate_world, {AgentProtocol.SYSTEM_AGENT: PrototypeConfig.round_setup_policy()}, WorldSyncAdapter.new())
	var expected: Dictionary = setup.context.duplicate(true)
	expected["phase"] = SessionPhase.Phase.ROUND_SETUP_PAUSED
	var result: WorldCommandResult = temporary.commit_batch(batch, expected)
	var safe_errors: Array = result.safe_dispatch_receipt().errors if result.status == "REJECTED" else []
	if not candidate_history.append_round_setup({"kind": "round_setup", "context": setup.context,
		"mode": payload.mode, "commands": payload.commands, "status": result.status,
		"revision_before": result.revision_before, "revision_after": result.revision_after, "errors": safe_errors}):
		return _reject("INVALID_HISTORY")
	if not result.completes(expected):
		_history._entries.assign(candidate_history.snapshot().entries)
		return _reject("ROUND_SETUP_REJECTED")
	candidate_world = temporary.get_world_snapshot()
	var next_sensing := RuntimeSensingCoordinator.new()
	var context: Dictionary = {"round_id": prepared_run.round_id, "branch_id": prepared_run.branch_id,
		"guess_cycle_id": 1, "report_cycle_id": 1, "sense_tick": 0}
	if not next_sensing.initialize_round(candidate_world, context, _session.get_ticks_per_report_period(), PrototypeConfig.system_dispatch_policy()):
		return _reject("INVALID_SENSING")
	var restored: Dictionary = _service.restore_trusted_snapshot(candidate_world.to_snapshot(), old_world.world_revision, prepared_run.next_entity_id, prepared_run.next_obstacle_id)
	if restored.get("ok") != true:
		return _reject(str(restored.get("errors", [{"code": "RESTORE_FAILED"}])[0].code))
	if not _session.complete_round_setup(setup.context, result):
		return _reject("ROUND_SESSION_COMMIT")
	_history._entries.assign(candidate_history.snapshot().entries)
	_run.accept_prepared(prepared_run)
	_sensing = next_sensing
	_checkpoint = null
	if _contact != null:
		_contact.invalidate_for_branch_change()
	if not _assistant_memory.on_branch_change({"round_id": prepared_run.round_id, "branch_id": prepared_run.branch_id, "parent_branch_id": 0}):
		_last_error = "ASSISTANT_MEMORY_FAULT"
		return false
	if not _capture() or not _session.resume_cycle(true):
		return _reject("CHECKPOINT_REJECTED")
	return true


func get_sensing() -> RuntimeSensingCoordinator:
	return _sensing


func get_run_snapshot() -> Dictionary:
	return _run.snapshot()


func get_checkpoint_snapshot() -> Dictionary:
	return _checkpoint.to_data() if _checkpoint != null else {}


func get_last_error() -> String:
	return _last_error


func matches(service: WorldCommandService, session: GameSession) -> bool:
	return _service == service and _session == session


func _capture() -> bool:
	var candidate: CycleCheckpoint = CycleCheckpoint.capture(_service.get_world_snapshot(), _session, _sensing)
	if candidate == null:
		return _reject("CHECKPOINT_REJECTED")
	_checkpoint = candidate
	return true


func _reject(code: String) -> bool:
	_last_error = code
	return false
