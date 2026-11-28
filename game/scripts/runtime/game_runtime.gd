extends Node
class_name GameRuntime


var auto_advance: bool = true

var _world_service: WorldCommandService
var _session: GameSession
var _view: RuntimeWorldView
var _movement_rules: Dictionary = {}
var _fault: String = ""
var _configured: bool = false
var _last_domain_events: Array[Dictionary] = []
var _active_contact_id: int = 0
var _sensing: RuntimeSensingCoordinator
var _report_callback_error: String = ""
var _report_committed_world: WorldState


func configure(
	world_service: WorldCommandService,
	session: GameSession,
	view: RuntimeWorldView,
	movement_rules: Dictionary
) -> void:
	_world_service = world_service
	_session = session
	_view = view
	_movement_rules = movement_rules.duplicate(true)
	_configured = _world_service != null and _session != null and _view != null


func configure_sensing(sensing: RuntimeSensingCoordinator) -> bool:
	if not _configured or _sensing != null or _session.get_cycle_snapshot().simulation_tick != 0 or _session.get_state_snapshot().phase != SessionPhase.Phase.ACTION or sensing == null or sensing.get_ticks_per_report_period() != _session.get_ticks_per_report_period() or sensing.get_system_view().is_empty():
		return false
	_sensing = sensing
	return true


func _physics_process(delta: float) -> void:
	if not auto_advance or not _configured or not _fault.is_empty():
		return
	var phase: int = _session.get_state_snapshot().phase
	if phase == SessionPhase.Phase.CONTACT_PAUSED:
		if Input.is_action_just_pressed("interact"):
			keep_current()
		return
	if phase != SessionPhase.Phase.ACTION:
		return
	var input_vector: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	step_once(input_vector, delta, Input.is_action_just_pressed("interact"), Input.is_action_just_pressed("cancel_interaction"))


func step_once(
	input_vector: Vector2,
	delta: float,
	interact_pressed: bool = false,
	cancel_pressed: bool = false
) -> Dictionary:
	if not _configured:
		return {"ok": false, "errors": [{"code": "NOT_CONFIGURED"}]}
	if not _fault.is_empty():
		return {"ok": false, "errors": [{"code": "RUNTIME_LOCKED", "message": _fault}]}
	var session_snapshot: Dictionary = _session.get_state_snapshot()
	if session_snapshot.phase != SessionPhase.Phase.ACTION:
		return {"ok": false, "errors": [{"code": "INVALID_PHASE"}]}
	var cycle_snapshot: Dictionary = _session.get_cycle_snapshot()
	var expected_tick: int = cycle_snapshot.simulation_tick + 1
	var candidate: WorldState = _world_service.get_world_snapshot()
	if candidate == null:
		return _fail("INVALID_WORLD")
	var previous_actor_cells: Dictionary = SensingKernel.actor_cells(candidate) if _sensing != null else {}
	var motion_errors: Array[Dictionary] = _view.step_motion(candidate, input_vector, delta, _movement_rules, expected_tick, interact_pressed, cancel_pressed)
	if not motion_errors.is_empty():
		return _fail(str(motion_errors))
	var interaction: Dictionary = _view.last_interaction
	var accept_contact: bool = interaction.contact_requested and not _session.is_guess_tick(expected_tick) and not (interaction.goal_complete and interaction.at_exit)
	if accept_contact:
		var contact: Dictionary = candidate.registry.get_entity(interaction.contact_id)
		if contact.is_empty() or contact.runtime_state.used:
			return _fail("INVALID_CONTACT")
		contact.runtime_state.used = true
		candidate.registry._put(contact)
	var sensing_context: Dictionary = {}
	var prepared: SensingStepResult = null
	if _sensing != null:
		sensing_context = {"round_id": session_snapshot.round_id, "branch_id": session_snapshot.branch_id,
			"guess_cycle_id": session_snapshot.guess_cycle_id,
			"report_cycle_id": _session.period_for_event_tick(expected_tick) + 1, "sense_tick": expected_tick}
		prepared = _sensing.prepare_step(previous_actor_cells, candidate, sensing_context)
		if not prepared.succeeded():
			return _fail(str(prepared.errors))
	var frame := WorldFrame.new(expected_tick, candidate.player_position, interaction.goal_complete, interaction.at_exit)
	var step := WorldStepResult.new(candidate, frame)
	step.domain_events.assign(interaction.events.duplicate(true))
	step.contact_requested = accept_contact
	step.contact_id = interaction.contact_id if accept_contact else 0
	var committed: Dictionary = _world_service.commit_runtime_step(expected_tick, step, session_snapshot, cycle_snapshot)
	if committed.get("ok") != true:
		return _fail(str(committed.get("errors", [])))
	var advanced: PhysicsStepResult = _session.advance_physics_step(frame)
	if not advanced.accepted:
		return _fail(advanced.error)
	if _sensing != null:
		var committed_world: WorldState = _world_service.get_world_snapshot()
		if not _sensing.commit_step(prepared, step.domain_events, committed_world, sensing_context):
			return _fail("SENSING_COMMIT_FAILED")
	if advanced.report_boundary != null:
		_report_callback_error = ""
		_report_committed_world = _world_service.get_world_snapshot() if _sensing != null else null
		var processed: bool = _session.process_report_boundary(_seal_report_batch, _update_system_view)
		_report_committed_world = null
		if not processed or not _report_callback_error.is_empty():
			if _sensing != null:
				_sensing.discard_report_boundary()
			return _fail("REPORT_BOUNDARY_FAILED")
		if _sensing != null and not _sensing.finish_report_boundary():
			_sensing.discard_report_boundary()
			return _fail("REPORT_PUBLISH_FAILED")
	if accept_contact and _session.get_state_snapshot().phase == SessionPhase.Phase.ACTION:
		if not _session.begin_contact():
			return _fail("CONTACT_START_FAILED")
		_active_contact_id = interaction.contact_id
	_last_domain_events.assign(step.domain_events.duplicate(true))
	return {"ok": true, "tick": expected_tick, "phase": _session.get_state_snapshot().phase, "errors": []}


func get_fault() -> String:
	return _fault


func get_last_domain_events() -> Array[Dictionary]:
	return _last_domain_events.duplicate(true)


func get_active_contact_id() -> int:
	if _session == null or _session.get_state_snapshot().phase != SessionPhase.Phase.CONTACT_PAUSED:
		_active_contact_id = 0
		return 0
	return _active_contact_id


func keep_current() -> bool:
	if _session.get_state_snapshot().phase != SessionPhase.Phase.CONTACT_PAUSED:
		return false
	var completed: bool = _session.end_contact(func(expected: Dictionary) -> WorldCommandResult:
		var batch := WorldCommandBatch.from_data({
			"context": AgentProtocol.serialize_context(expected),
			"source": "contact",
			"base_world_revision": _world_service.get_world_snapshot().world_revision,
			"mode": "KEEP_CURRENT",
			"commands": [],
		})
		return _world_service.commit_batch(batch, expected)
	)
	if completed:
		_active_contact_id = 0
	return completed


func _fail(message: String) -> Dictionary:
	_fault = message
	print("GAME RUNTIME FAULT: " + message)
	return {"ok": false, "errors": [{"code": "RUNTIME_FAULT", "message": message}]}


func _seal_report_batch(boundary: ReportBoundary) -> void:
	if _sensing != null and not _sensing.seal_report_batch(boundary):
		_report_callback_error = "REPORT_SEAL_FAILED"


func _update_system_view(boundary: ReportBoundary) -> void:
	if _sensing == null or not _report_callback_error.is_empty():
		return
	if not _sensing.update_system_view(boundary, _report_committed_world):
		_report_callback_error = "REPORT_VIEW_UPDATE_FAILED"
