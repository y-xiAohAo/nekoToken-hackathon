extends RefCounted
class_name GameSession


var _rules: SessionRules
var _state: SessionState = SessionState.new()
var _cycle: CycleState = CycleState.new()
var _pending_report_boundary: ReportBoundary
var _pending_world_frame: WorldFrame
var _processing_report_boundary: bool = false
var _pending_round_success: bool = false
var _next_request_id: int = 1
var _processing_deployment: bool = false


func _init(p_rules: SessionRules) -> void:
	_rules = SessionRules.new(
		p_rules.ticks_per_report_period,
		p_rules.report_periods_per_guess_cycle
	)


func advance_physics_step(frame: WorldFrame) -> PhysicsStepResult:
	if not _rules.is_valid():
		return PhysicsStepResult.new(false, "Session rules are invalid.")
	if _state.phase != SessionPhase.Phase.ACTION:
		return PhysicsStepResult.new(false, "Physics can only advance during ACTION.")
	if frame == null or frame.simulation_tick != _cycle.clock.tick + 1:
		return PhysicsStepResult.new(false, "WorldFrame tick must be the next simulation tick.")

	var committed_frame: WorldFrame = frame.snapshot_copy()
	_cycle.clock.advance_one_tick()
	if committed_frame.simulation_tick % _rules.ticks_per_report_period != 0:
		if committed_frame.goal_complete and committed_frame.at_exit:
			_finish_round(SessionPhase.RoundResult.SUCCESS)
		return PhysicsStepResult.new(true)

	var is_guess_boundary: bool = (
		_cycle.sealed_reports_in_guess_cycle + 1 >= _rules.report_periods_per_guess_cycle
	)
	_pending_report_boundary = ReportBoundary.new(
		_state.round_id,
		_state.branch_id,
		_state.guess_cycle_id,
		_cycle.report_period_id + 1,
		committed_frame.simulation_tick - _rules.ticks_per_report_period,
		committed_frame.simulation_tick,
		is_guess_boundary
	)
	_pending_world_frame = committed_frame
	_pending_round_success = committed_frame.goal_complete and committed_frame.at_exit
	_state.phase = SessionPhase.Phase.REPORT_BOUNDARY
	return PhysicsStepResult.new(true, "", _pending_report_boundary.snapshot_copy())


func process_report_boundary(
	seal_batch: Callable,
	update_view: Callable
) -> bool:
	if _state.phase != SessionPhase.Phase.REPORT_BOUNDARY or _pending_report_boundary == null or _processing_report_boundary:
		return false
	if not seal_batch.is_valid() or not update_view.is_valid():
		return false

	_processing_report_boundary = true
	seal_batch.call(_pending_report_boundary.snapshot_copy())
	update_view.call(_pending_report_boundary.snapshot_copy())
	_complete_report_boundary()
	_processing_report_boundary = false
	return true


func _complete_report_boundary() -> void:

	_cycle.report_period_id += 1
	_cycle.sealed_reports_in_guess_cycle += 1
	var is_guess_boundary: bool = _pending_report_boundary.is_guess_boundary
	var boundary_frame: WorldFrame = _pending_world_frame
	_pending_report_boundary = null
	_pending_world_frame = null
	_state.phase = SessionPhase.Phase.ACTION

	if is_guess_boundary:
		_state.phase = SessionPhase.Phase.GUESS_PAUSED
		_state.frozen_guess_frame = boundary_frame
		_state.active_request_context = AgentProtocol.make_request_context(
			AgentProtocol.SYSTEM_AGENT,
			_next_request_id,
			_state.round_id,
			_state.branch_id,
			_state.guess_cycle_id
		)
		_next_request_id += 1
	elif _pending_round_success:
		_finish_round(SessionPhase.RoundResult.SUCCESS)

	_pending_round_success = false


func period_for_event_tick(event_tick: int) -> int:
	if event_tick < 0 or not _rules.is_valid():
		return -1
	return event_tick / _rules.ticks_per_report_period


func begin_contact() -> bool:
	if _state.phase != SessionPhase.Phase.ACTION:
		return false
	_state.phase = SessionPhase.Phase.CONTACT_PAUSED
	renew_world_request()
	return true


func end_contact(deploy: Callable = Callable()) -> bool:
	if _state.phase != SessionPhase.Phase.CONTACT_PAUSED:
		return false
	if not _deploy_world(deploy):
		return false
	_state.active_request_context = {}
	_state.phase = SessionPhase.Phase.ACTION
	return true


func accept_guess_result(context: Dictionary, hit: bool) -> bool:
	if _state.phase != SessionPhase.Phase.GUESS_PAUSED:
		return false
	if not AgentProtocol.contexts_match(context, _state.active_request_context):
		return false
	if context.get("role", "") != AgentProtocol.SYSTEM_AGENT:
		return false

	_state.active_request_context = {}
	if hit:
		_state.phase = SessionPhase.Phase.RESET_CHOICE
	elif _state.frozen_guess_frame.goal_complete and _state.frozen_guess_frame.at_exit:
		_finish_round(SessionPhase.RoundResult.SUCCESS)
	else:
		_state.phase = SessionPhase.Phase.DISPATCH_PAUSED
		renew_world_request()
	return true


func complete_dispatch(deploy: Callable = Callable()) -> bool:
	if _state.phase != SessionPhase.Phase.DISPATCH_PAUSED:
		return false
	if not _deploy_world(deploy):
		return false
	_state.active_request_context = {}
	_state.guess_cycle_id += 1
	_cycle.sealed_reports_in_guess_cycle = 0
	_state.frozen_guess_frame = null
	_state.phase = SessionPhase.Phase.CYCLE_START_PENDING
	return true


func renew_world_request() -> Dictionary:
	if _processing_deployment or _state.phase not in [SessionPhase.Phase.CONTACT_PAUSED, SessionPhase.Phase.DISPATCH_PAUSED]:
		return {}
	var role: String = AgentProtocol.PLAYER_ASSISTANT if _state.phase == SessionPhase.Phase.CONTACT_PAUSED else AgentProtocol.SYSTEM_AGENT
	_state.active_request_context = AgentProtocol.make_request_context(role, _next_request_id, _state.round_id, _state.branch_id, _state.guess_cycle_id)
	_next_request_id += 1
	return _state.active_request_context.duplicate(true)


func _deploy_world(deploy: Callable) -> bool:
	if _processing_deployment or not deploy.is_valid():
		return false
	var expected: Dictionary = _state.active_request_context.duplicate(true)
	expected["phase"] = _state.phase
	_processing_deployment = true
	var result: Variant = deploy.call(expected.duplicate(true))
	_processing_deployment = false
	return result is WorldCommandResult and result.completes(expected)


func resume_cycle(snapshot_saved: bool) -> bool:
	if _state.phase != SessionPhase.Phase.CYCLE_START_PENDING or not snapshot_saved:
		return false
	_state.phase = SessionPhase.Phase.ACTION
	return true


func get_pending_report_boundary() -> ReportBoundary:
	if _pending_report_boundary == null:
		return null
	return _pending_report_boundary.snapshot_copy()


func get_state_snapshot() -> Dictionary:
	return _state.snapshot()


func get_cycle_snapshot() -> Dictionary:
	return _cycle.snapshot()


func _finish_round(result: SessionPhase.RoundResult) -> void:
	_state.phase = SessionPhase.Phase.ROUND_END
	_state.round_result = result
	_state.active_request_context = {}
	_pending_report_boundary = null
	_pending_world_frame = null
