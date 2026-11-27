extends RefCounted
class_name SessionKernelTests


var passed: int = 0
var failed: int = 0


func run() -> Dictionary:
	_check(_test_time_and_boundaries(), "_test_time_and_boundaries completed")
	_check(_test_contact_and_snapshot(), "_test_contact_and_snapshot completed")
	_check(_test_guess_priority(), "_test_guess_priority completed")
	_check(_test_round_success(), "_test_round_success completed")
	_check(_test_dispatch_and_context(), "_test_dispatch_and_context completed")
	_check(_test_agent_views(), "_test_agent_views completed")
	return {"passed": passed, "failed": failed}


func _check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		push_error("TEST FAILED: " + label)


func _frame(tick: int, goal: bool = false, exit_reached: bool = false) -> WorldFrame:
	return WorldFrame.new(tick, Vector2(tick * 2.0, 3.0), goal, exit_reached)


func _advance(session: GameSession, tick: int, goal: bool = false, exit_reached: bool = false) -> PhysicsStepResult:
	return session.advance_physics_step(_frame(tick, goal, exit_reached))


func _test_time_and_boundaries() -> bool:
	var session := GameSession.new(SessionRules.new(2, 2))
	_check(session.period_for_event_tick(0) == 0, "first event belongs to first period")
	_check(session.period_for_event_tick(1) == 0, "end-minus-one remains in first period")
	_check(session.period_for_event_tick(2) == 1, "end tick belongs to next period")
	_check(session.period_for_event_tick(-1) == -1, "negative event tick rejected")
	_check(_advance(session, 2).accepted == false, "skipped physics tick rejected")
	_check(_advance(session, 1).accepted, "first physics tick accepted")
	var boundary_result := _advance(session, 2)
	_check(boundary_result.accepted and boundary_result.report_boundary != null, "report boundary emitted once")
	_check(boundary_result.report_boundary.start_tick == 0 and boundary_result.report_boundary.end_tick == 2, "first report is half-open [0,2)")
	_check(not boundary_result.report_boundary.snapshot().has("frame"), "report boundary does not expose true player frame")
	_check(_advance(session, 3).accepted == false, "report boundary freezes physics")
	_check(session.get_cycle_snapshot()["simulation_tick"] == 2, "clock frozen at boundary")
	var sequence: Array[String] = []
	var reentrant_result: Array[bool] = []
	var completed := session.process_report_boundary(
		func(boundary: ReportBoundary) -> void:
			sequence.append("seal:%d" % boundary.report_period_id)
			reentrant_result.append(session.process_report_boundary(func(_b: ReportBoundary) -> void: pass, func(_b: ReportBoundary) -> void: pass)),
		func(_boundary: ReportBoundary) -> void:
			sequence.append("view")
	)
	_check(completed, "whole report batch processed")
	_check(sequence == ["seal:1", "view"], "report sequence is serial")
	_check(reentrant_result == [false], "report boundary cannot be processed twice by reentrant callback")
	_check(session.get_cycle_snapshot()["sealed_reports_in_guess_cycle"] == 1, "one whole batch counted")
	_check(session.process_report_boundary(func(_b: ReportBoundary) -> void: pass, func(_b: ReportBoundary) -> void: pass) == false, "duplicate boundary rejected")
	_check(_advance(session, 3).accepted, "action resumes after ordinary boundary")
	var guess_boundary := _advance(session, 4)
	_check(guess_boundary.report_boundary != null and guess_boundary.report_boundary.is_guess_boundary, "second report is guess boundary")
	_check(session.process_report_boundary(func(_b: ReportBoundary) -> void: pass, func(_b: ReportBoundary) -> void: pass), "guess batch processed")
	_check(session.get_state_snapshot()["phase"] == SessionPhase.Phase.GUESS_PAUSED, "guess starts only after full batch")
	_check(_advance(session, 5).accepted == false, "guess pause freezes physics")
	return true


func _test_contact_and_snapshot() -> bool:
	var session := GameSession.new(SessionRules.new(3, 2))
	_check(session.begin_contact(), "contact opens during action")
	_check(_advance(session, 1).accepted == false, "contact freezes clock")
	_check(session.get_cycle_snapshot()["simulation_tick"] == 0, "contact leaves clock at zero")
	_check(session.end_contact(_keep_current), "contact closes")
	_check(_advance(session, 1).accepted, "physics resumes after contact")
	var snapshot: Dictionary = session.get_state_snapshot()
	snapshot["phase"] = SessionPhase.Phase.ROUND_END
	_check(session.get_state_snapshot()["phase"] == SessionPhase.Phase.ACTION, "external snapshot cannot mutate phase")
	return true


func _test_guess_priority() -> bool:
	var session := GameSession.new(SessionRules.new(2, 1))
	_check(_advance(session, 1).accepted, "pre-guess step accepted")
	var result := _advance(session, 2, true, true)
	_check(result.report_boundary != null, "exit at guess tick still creates report")
	_check(session.process_report_boundary(func(_b: ReportBoundary) -> void: pass, func(_b: ReportBoundary) -> void: pass), "guess boundary completes")
	_check(session.get_state_snapshot()["phase"] == SessionPhase.Phase.GUESS_PAUSED, "guess outranks exit")
	var context: Dictionary = session.get_state_snapshot()["active_request_context"]
	_check(session.accept_guess_result(context, false), "valid miss accepted")
	_check(session.get_state_snapshot()["phase"] == SessionPhase.Phase.ROUND_END, "miss at exit ends round")
	_check(session.get_state_snapshot()["round_result"] == SessionPhase.RoundResult.SUCCESS, "miss at exit succeeds")
	_check(session.complete_dispatch() == false, "success skips dispatch")

	var hit_session := GameSession.new(SessionRules.new(1, 1))
	var hit_boundary := _advance(hit_session, 1, true, true)
	_check(hit_boundary.report_boundary != null, "hit scenario boundary exists")
	_check(hit_session.process_report_boundary(func(_b: ReportBoundary) -> void: pass, func(_b: ReportBoundary) -> void: pass), "hit scenario report completes")
	var hit_context: Dictionary = hit_session.get_state_snapshot()["active_request_context"]
	_check(hit_session.accept_guess_result(hit_context, true), "valid hit accepted")
	_check(hit_session.get_state_snapshot()["phase"] == SessionPhase.Phase.RESET_CHOICE, "hit outranks exit success")
	return true


func _test_round_success() -> bool:
	var direct_session := GameSession.new(SessionRules.new(3, 2))
	_check(_advance(direct_session, 1, true, true).accepted, "non-boundary exit accepted")
	_check(direct_session.get_state_snapshot()["phase"] == SessionPhase.Phase.ROUND_END, "non-boundary exit succeeds immediately")

	var boundary_session := GameSession.new(SessionRules.new(2, 2))
	_check(_advance(boundary_session, 1).accepted, "step before ordinary boundary accepted")
	var boundary := _advance(boundary_session, 2, true, true)
	_check(boundary.report_boundary != null and not boundary.report_boundary.is_guess_boundary, "ordinary report happens before exit success")
	_check(boundary_session.get_state_snapshot()["phase"] == SessionPhase.Phase.REPORT_BOUNDARY, "boundary waits for whole report")
	_check(boundary_session.process_report_boundary(func(_b: ReportBoundary) -> void: pass, func(_b: ReportBoundary) -> void: pass), "ordinary exit batch completes")
	_check(boundary_session.get_state_snapshot()["phase"] == SessionPhase.Phase.ROUND_END, "ordinary boundary then succeeds")
	return true


func _test_dispatch_and_context() -> bool:
	var session := GameSession.new(SessionRules.new(1, 1))
	_check(_advance(session, 1).report_boundary != null, "dispatch scenario boundary exists")
	_check(session.process_report_boundary(func(_b: ReportBoundary) -> void: pass, func(_b: ReportBoundary) -> void: pass), "dispatch scenario report completes")
	var expected: Dictionary = session.get_state_snapshot()["active_request_context"]
	var stale: Dictionary = expected.duplicate(true)
	stale["branch_id"] += 1
	_check(session.accept_guess_result(stale, false) == false, "wrong branch guess rejected")
	_check(session.get_state_snapshot()["phase"] == SessionPhase.Phase.GUESS_PAUSED, "stale guess cannot change phase")
	_check(session.accept_guess_result(expected, false), "current miss accepted")
	_check(session.get_state_snapshot()["phase"] == SessionPhase.Phase.DISPATCH_PAUSED, "miss without exit enters dispatch")
	_check(session.complete_dispatch(_keep_current), "dispatch completes to next cycle preparation")
	_check(session.get_state_snapshot()["phase"] == SessionPhase.Phase.CYCLE_START_PENDING, "snapshot gate remains paused")
	_check(_advance(session, 2).accepted == false, "snapshot gate freezes clock")
	_check(session.resume_cycle(false) == false, "cycle cannot resume without snapshot")
	_check(session.resume_cycle(true), "cycle resumes after snapshot confirmation")
	_check(session.get_state_snapshot()["guess_cycle_id"] == 2, "guess cycle increments once")
	_check(session.get_cycle_snapshot()["sealed_reports_in_guess_cycle"] == 0, "new cycle clears batch count")
	return true


func _test_agent_views() -> bool:
	var system_context := AgentProtocol.make_request_context(AgentProtocol.SYSTEM_AGENT, 7, 1, 3, 2)
	var player_context := AgentProtocol.make_request_context(AgentProtocol.PLAYER_ASSISTANT, 8, 1, 3, 2)
	var system_request := AgentProtocol.make_system_request(system_context, {"cells": []}, [], [])
	var player_request := AgentProtocol.make_player_assistant_request(player_context, "看到灯", [], [], [])
	var system_json := AgentProtocol.serialize_request(system_request)
	var player_json := AgentProtocol.serialize_request(player_request)
	_check(not system_json.contains("player_world_position"), "system request hides true player coordinate")
	_check(not system_json.contains("contact_source"), "system request hides contact source")
	_check(not player_json.contains("static_map"), "assistant request hides static map")
	_check(not player_json.contains("device_configuration"), "assistant request hides device positions")
	_check(not player_json.contains("reports"), "assistant request hides system reports")
	var response: Dictionary = {"context": system_context.duplicate(true), "status": "ok", "payload": {}}
	_check(AgentProtocol.response_matches(response, system_context), "matching response accepted")
	response["status"] = "timeout"
	_check(not AgentProtocol.response_matches(response, system_context), "timeout is not a valid guess")
	response["status"] = "ok"
	var new_branch: Dictionary = system_context.duplicate(true)
	new_branch["branch_id"] = 4
	_check(not AgentProtocol.response_matches(response, new_branch), "old branch reply rejected")
	var injected_system: Dictionary = system_request.duplicate(true)
	injected_system["view"]["player_world_position"] = [12, 7]
	_check(not AgentProtocol.serialize_request(injected_system).contains("player_world_position"), "system serializer projects allowed top-level fields")
	injected_system["view"]["static_map"]["contact_source"] = "private"
	_check(AgentProtocol.serialize_request(injected_system).is_empty(), "system serializer rejects nested private fields")
	var injected_player: Dictionary = player_request.duplicate(true)
	injected_player["view"]["static_map"] = {"cells": []}
	_check(not AgentProtocol.serialize_request(injected_player).contains("static_map"), "player serializer projects allowed top-level fields")
	injected_player["view"]["conversation"].append({"reports": []})
	_check(AgentProtocol.serialize_request(injected_player).is_empty(), "player serializer rejects nested system fields")
	_check(AgentProtocol.make_system_request(player_context, {}, [], []).is_empty(), "system builder rejects assistant role")
	_check(AgentProtocol.make_player_assistant_request(system_context, "", [], [], []).is_empty(), "assistant builder rejects system role")
	_check(not AgentProtocol.response_matches({"context": 7, "status": "ok", "payload": {}}, system_context), "malformed response context rejected")
	var invalid_context: Dictionary = system_context.duplicate(true)
	invalid_context["branch_id"] = 0
	_check(AgentProtocol.serialize_request({"context": invalid_context, "view": system_request["view"]}).is_empty(), "request with invalid identity is rejected")
	return true


func _keep_current(expected: Dictionary) -> WorldCommandResult:
	var result := WorldCommandResult.new()
	result.status = "UNCHANGED"
	result.context = AgentProtocol.serialize_context(expected)
	return result
