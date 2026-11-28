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
var _gateway: SimulatedAgentGateway
var _history: SystemAgentHistory
var _agent_rules: Dictionary = {}
var _agent_pending_context: Dictionary = {}
var _agent_pending_type: String = ""
var _agent_pending_sent: bool = false
var _previous_rejection: Variant = null


func configure_agent(gateway: SimulatedAgentGateway, history: SystemAgentHistory, agent_rules: Dictionary) -> bool:
	if not _configured or _sensing == null or _gateway != null or gateway == null or history == null or not DeviceRegistry.plain(agent_rules):
		return false
	if not DeviceRegistry.fields(agent_rules, ["location_constraints", "dispatch_policy", "max_dispatch_attempts"]):
		return false
	if not AgentProtocol._constraints_valid(agent_rules.location_constraints) or not agent_rules.dispatch_policy is Dictionary or typeof(agent_rules.max_dispatch_attempts) != TYPE_INT or agent_rules.max_dispatch_attempts < 1:
		return false
	_gateway = gateway
	_history = history
	_agent_rules = agent_rules.duplicate(true)
	return true


func pump_agent() -> Dictionary:
	if not _configured or _gateway == null or _sensing == null or not _fault.is_empty():
		return {"ok": false, "errors": [{"code": "AGENT_UNAVAILABLE"}]}
	var state: Dictionary = _session.get_state_snapshot()
	var request_type: String = state.get("active_request_type", "")
	if state.phase == SessionPhase.Phase.GUESS_PAUSED and request_type != "location_guess":
		return _fail("AGENT_REQUEST_TYPE")
	if state.phase == SessionPhase.Phase.DISPATCH_PAUSED and request_type != "dispatch":
		return _fail("AGENT_REQUEST_TYPE")
	if state.phase not in [SessionPhase.Phase.GUESS_PAUSED, SessionPhase.Phase.DISPATCH_PAUSED]:
		return {"ok": false, "errors": [{"code": "INVALID_PHASE"}]}
	var context: Dictionary = state.active_request_context
	if not AgentProtocol._system_context(context):
		return _fail("AGENT_CONTEXT")
	if _agent_pending_sent:
		return {"ok": false, "errors": [{"code": "AGENT_ALREADY_PENDING"}]}
	var view: Dictionary = _sensing.get_system_view()
	if view.is_empty() or view.reports.is_empty():
		return _fail("AGENT_REPORT_NOT_PUBLISHED")
	var cycle: Dictionary = _session.get_cycle_snapshot()
	var frozen: Dictionary = state.frozen_guess_frame
	if frozen.is_empty() or frozen.get("simulation_tick") != cycle.simulation_tick:
		return _fail("AGENT_FROZEN_FRAME")
	var last: Dictionary = view.reports[-1]
	if last.get("end_tick") != cycle.simulation_tick or last.get("report_period_id") != cycle.report_period_id or last.get("round_id") != state.round_id or last.get("branch_id") != state.branch_id or last.get("guess_cycle_id") != state.guess_cycle_id:
		return _fail("AGENT_REPORT_IDENTITY")
	view["history"] = _history.snapshot().entries
	var as_of: Dictionary = {"simulation_tick": cycle.simulation_tick, "report_period_id": cycle.report_period_id}
	var request: Dictionary = AgentProtocol.make_location_request(context, view, as_of, _agent_rules.location_constraints) if request_type == "location_guess" else AgentProtocol.make_dispatch_request(context, view, as_of, _agent_rules.dispatch_policy, _previous_rejection)
	if request.is_empty():
		return _fail("AGENT_REQUEST_INVALID")
	_agent_pending_context = context.duplicate(true)
	_agent_pending_type = request_type
	_agent_pending_sent = true
	var sent_context: Dictionary = context.duplicate(true)
	var sent_type: String = request_type
	if not _gateway.submit(request, func(result: Variant) -> void: on_agent_result(sent_context, sent_type, result)):
		_agent_pending_sent = false
		return _fail("AGENT_GATEWAY_SUBMIT")
	return {"ok": true, "request_type": request_type, "context": context.duplicate(true)}


func on_agent_result(sent_context: Dictionary, request_type: String, result: Variant) -> void:
	if not _configured or not _fault.is_empty():
		return
	var state: Dictionary = _session.get_state_snapshot()
	# Old requests lose authority when a retry allocates a new request ID.
	if not AgentProtocol.contexts_match(sent_context, state.active_request_context):
		return
	if not _agent_pending_sent or sent_context != _agent_pending_context:
		return
	if request_type != _agent_pending_type or request_type != state.get("active_request_type"):
		_fail("AGENT_REQUEST_TYPE")
		return
	if (request_type == "location_guess" and state.phase != SessionPhase.Phase.GUESS_PAUSED) or (request_type == "dispatch" and state.phase != SessionPhase.Phase.DISPATCH_PAUSED):
		_fail("AGENT_PHASE")
		return
	_agent_pending_sent = false
	_agent_pending_context = {}
	_agent_pending_type = ""
	if not DeviceRegistry.fields(result, ["kind", "raw"]):
		_fail("AGENT_GATEWAY_RESULT")
		return
	if result.kind != "response" or result.raw == null:
		_fail("AGENT_" + str(result.kind).to_upper())
		return
	if request_type == "location_guess":
		_accept_location(sent_context, result.raw, state)
	else:
		_accept_dispatch(sent_context, result.raw)


func get_agent_snapshot() -> Dictionary:
	return {"fault": _fault, "pending_context": _agent_pending_context.duplicate(true),
		"pending_request_type": _agent_pending_type, "pending_sent": _agent_pending_sent,
		"history": _history.snapshot() if _history != null else {"entries": []}}


func _accept_location(context: Dictionary, raw: Variant, state: Dictionary) -> void:
	var world: WorldState = _world_service.get_world_snapshot()
	if world == null:
		_fail("AGENT_WORLD_MISSING")
		return
	var parsed: Dictionary = AgentProtocol.parse_location_response(raw, context, _agent_rules.location_constraints, world.grid_size)
	if not parsed.ok:
		_fail(parsed.error)
		return
	var frozen: Dictionary = state.frozen_guess_frame
	if frozen.get("world_revision") != world.world_revision or not frozen.get("player_world_position") is Vector2 or not world.player_position.is_equal_approx(frozen.player_world_position):
		_fail("AGENT_FROZEN_WORLD_MISMATCH")
		return
	var player_cell: Vector2i = world.world_to_cell(frozen.player_world_position)
	if not world.in_bounds(player_cell):
		_fail("AGENT_FROZEN_POSITION")
		return
	var location: Dictionary = parsed.payload
	var x: int = location.origin_cell[0]
	var y: int = location.origin_cell[1]
	var hit: bool = x <= player_cell.x and player_cell.x < x + location.size[0] and y <= player_cell.y and player_cell.y < y + location.size[1]
	if not _session.accept_guess_result(context, hit):
		_fail("AGENT_GUESS_COMMIT")
		return
	var cycle: Dictionary = _session.get_cycle_snapshot()
	if not _history.append_guess({"kind": "guess", "context": context, "as_of": {"simulation_tick": cycle.simulation_tick, "report_period_id": cycle.report_period_id},
		"origin_cell": location.origin_cell, "size": location.size, "verdict": "HIT" if hit else "MISS"}):
		_fail("AGENT_HISTORY")


func _accept_dispatch(context: Dictionary, raw: Variant) -> void:
	var parsed: Dictionary = AgentProtocol.parse_dispatch_response(raw, context)
	if not parsed.ok:
		_fail(parsed.error)
		return
	var payload: Dictionary = parsed.payload
	var before: Dictionary = _world_service.get_world_snapshot().to_snapshot()
	var box: Dictionary = {"result": null}
	var complete: bool = _session.complete_dispatch(func(expected: Dictionary) -> WorldCommandResult:
		var batch: WorldCommandBatch = WorldCommandBatch.from_data({"context": AgentProtocol.serialize_context(expected),
			"source": "dispatch", "base_world_revision": before.world_revision,
			"mode": payload.mode, "commands": payload.commands})
		box.result = _world_service.commit_batch(batch, expected) if batch != null else null
		return box.result
	)
	var receipt: WorldCommandResult = box.result
	if receipt == null:
		_fail("AGENT_DISPATCH_COMMIT")
		return
	if not complete:
		if receipt.status != "REJECTED" or receipt.errors.is_empty() or _world_service.get_world_snapshot().to_snapshot() != before:
			_fail("AGENT_DISPATCH_INVARIANT")
			return
		var fault_code: String = receipt.errors[0].code
		if fault_code in ["INVALID_CONTEXT", "STALE_BRANCH", "INVALID_PHASE", "STALE_WORLD", "SYNC_PREPARE_FAILED", "SYNC_ACTIVATION_FAILED", "INVALID_WORLD", "INVALID_COMMAND"]:
			_fail("AGENT_DISPATCH_" + fault_code)
			return
	var safe_errors: Array = receipt.safe_dispatch_receipt().errors if receipt.status == "REJECTED" else []
	if not _history.append_dispatch({"kind": "dispatch", "context": context, "mode": payload.mode,
		"commands": payload.commands, "status": receipt.status, "revision_before": receipt.revision_before,
		"revision_after": receipt.revision_after, "errors": safe_errors}):
		_fail("AGENT_HISTORY")
		return
	if complete:
		_previous_rejection = null
		print("MODULE5_CYCLE_START_PENDING")
		return
	var safe: Dictionary = receipt.safe_dispatch_receipt()
	var decision: Dictionary = _session.note_dispatch_rejection(context, safe, _agent_rules.max_dispatch_attempts)
	if decision.get("retry") == true:
		_previous_rejection = safe
	elif decision.get("exhausted") == true:
		_fail("AGENT_DISPATCH_ATTEMPTS_EXHAUSTED")
	else:
		_fail("AGENT_DISPATCH_RETRY_STATE")


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
	if phase in [SessionPhase.Phase.GUESS_PAUSED, SessionPhase.Phase.DISPATCH_PAUSED] and _gateway != null:
		if not _agent_pending_sent:
			pump_agent()
		return
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
	var frame := WorldFrame.new(expected_tick, candidate.player_position, interaction.goal_complete, interaction.at_exit, candidate.world_revision)
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
