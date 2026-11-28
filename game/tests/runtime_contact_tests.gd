extends RefCounted
class_name RuntimeContactTests

class RejectPrepare extends SceneWorldSyncAdapter:
	func prepare(_previous: Dictionary, _candidate: Dictionary, _changes: Dictionary) -> Dictionary:
		return {"ok": false, "errors": [{"code": "INJECTED_PREPARE"}]}

class RejectActivate extends SceneWorldSyncAdapter:
	func activate(prepared: Dictionary) -> bool:
		for node: Node in prepared.get("changed", {}).values():
			node.queue_free()
		return false

var passed: int = 0
var failed: int = 0

func run() -> Dictionary:
	await _confirm_and_report()
	await _reject_and_keep()
	await _sync_rejection_and_fault()
	await _main_scene_ui()
	return {"passed": passed, "failed": failed}

func _fixture(sync_mode: String = "") -> Dictionary:
	var level: Dictionary = PrototypeConfig.level_data()
	level.player_spawn = [96.0, 300.0]
	level.initial_entities[0].parameters.view_radius = 512.0
	level.initial_entities[0].parameters.fov_angle = TAU
	var template: LevelTemplate = LevelTemplate.from_data(level)
	if template == null:
		push_error("CONTACT FIXTURE: invalid template")
		return {}
	var world: WorldState = template.instantiate_world()
	if world == null:
		push_error("CONTACT FIXTURE: world null")
		return {}
	var view := RuntimeWorldView.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(view)
	if not view.build_from_world(world):
		push_error("CONTACT FIXTURE: view build failed")
		view.queue_free()
		return {}
	var adapter: SceneWorldSyncAdapter = SceneWorldSyncAdapter.new(view)
	if sync_mode == "prepare":
		adapter = RejectPrepare.new(view)
	elif sync_mode == "activate":
		adapter = RejectActivate.new(view)
	var service := WorldCommandService.new(world, PrototypeConfig.player_assistant_policy(), adapter)
	var session := GameSession.new(PrototypeConfig.make_session_rules())
	var assistant := SimulatedPlayerAssistant.new(PrototypeConfig.simulated_assistant_scan())
	var contact := ContactSessionController.new(session, service, view, assistant)
	var runtime := GameRuntime.new()
	view.add_child(runtime)
	runtime.auto_advance = false
	runtime.configure(service, session, view, PrototypeConfig.movement_rules())
	if not runtime.configure_contact(contact):
		push_error("CONTACT FIXTURE: runtime contact setup failed")
		view.queue_free()
		return {}
	var sensing := RuntimeSensingCoordinator.new()
	var state: Dictionary = session.get_state_snapshot()
	var context: Dictionary = {"round_id": state.round_id, "branch_id": state.branch_id, "guess_cycle_id": state.guess_cycle_id,
		"report_cycle_id": session.period_for_event_tick(0) + 1, "sense_tick": 0}
	if not sensing.initialize_round(service.get_world_snapshot(), context, session.get_ticks_per_report_period()) or not runtime.configure_sensing(sensing):
		push_error("CONTACT FIXTURE: sensing setup failed")
		view.queue_free()
		return {}
	return {"view": view, "service": service, "session": session, "runtime": runtime, "assistant": assistant, "sensing": sensing}

func _enter(f: Dictionary) -> bool:
	await (Engine.get_main_loop() as SceneTree).physics_frame
	var step: Dictionary = f.runtime.step_once(Vector2.ZERO, 1.0 / 60.0, true)
	return step.get("ok") == true and f.session.get_state_snapshot().phase == SessionPhase.Phase.CONTACT_PAUSED

func _confirm_and_report() -> void:
	var f: Dictionary = _fixture()
	_check(not f.is_empty(), "fixture created")
	if f.is_empty(): return
	_check(await _enter(f), "contact entered")
	var contact_id: int = f.runtime.get_active_contact_id()
	_check(contact_id > 0 and f.service.get_world_snapshot().registry.get_entity(contact_id).runtime_state.used, "contact used on entry")
	var old_tick: int = f.session.get_cycle_snapshot().simulation_tick
	var old_revision: int = f.service.get_world_snapshot().world_revision
	var old_view: Dictionary = f.sensing.get_system_view()
	var paused_world: Dictionary = f.service.get_world_snapshot().to_snapshot()
	var paused_sensing: Dictionary = f.sensing.snapshot()
	f.runtime.auto_advance = true
	for _i: int in 3:
		await (Engine.get_main_loop() as SceneTree).physics_frame
	f.runtime.auto_advance = false
	_check(f.service.get_world_snapshot().to_snapshot() == paused_world and f.sensing.snapshot() == paused_sensing and f.session.get_cycle_snapshot().simulation_tick == old_tick, "paused physics freezes world and sensing")
	var camera_id: int = f.view.camera_at_screen_position(Vector2(416, 96))
	_check(camera_id > 0 and f.runtime.select_contact_target_at(Vector2(416, 96)), "visible camera selected by screen click")
	_check(not f.runtime.select_contact_target_at(Vector2(700, 500)), "empty click rejected")
	_check(f.runtime.submit_contact_text("请看这台摄像头"), "structured proposal delivered")
	var proposal: Dictionary = f.runtime.get_contact_ui_snapshot().proposal
	_check(proposal.values.size() == 2, "both fields displayed together")
	_check(f.session.get_cycle_snapshot().simulation_tick == old_tick and f.service.get_world_snapshot().world_revision == old_revision, "proposal freezes world and tick")
	_check(f.runtime.confirm_contact_proposal(proposal.token), "player confirmation commits")
	var changed: WorldState = f.service.get_world_snapshot()
	_check(changed.world_revision == old_revision + 1 and f.session.get_state_snapshot().phase == SessionPhase.Phase.ACTION, "one revision and resumed action")
	_check(is_equal_approx(changed.registry.get_entity(camera_id).parameters.scan_center, 0.2) and is_equal_approx(changed.registry.get_entity(camera_id).parameters.scan_half_angle, 0.4), "same camera receives both values")
	_check(f.session.get_cycle_snapshot().simulation_tick == old_tick and f.sensing.get_system_view() == old_view, "no early sensing report or config reveal")
	_check(not f.runtime.confirm_contact_proposal(proposal.token), "token cannot replay")
	for _i: int in 29:
		var step: Dictionary = f.runtime.step_once(Vector2.ZERO, 1.0 / 60.0)
		if not step.get("ok"):
			_check(false, "post-deployment physics step")
			break
	_check(f.session.get_cycle_snapshot().simulation_tick == 30, "normal report boundary reached")
	var published: Dictionary = f.sensing.get_system_view()
	var public_camera: Dictionary = published.world.cameras[0] if published.has("world") and not published.world.cameras.is_empty() else (published.device_configuration[0] if published.has("device_configuration") and not published.device_configuration.is_empty() else {})
	_check(published.reports.size() == 1 and not public_camera.is_empty() and is_equal_approx(public_camera.parameters.scan_center, 0.2), "new config published at normal boundary")
	if published.reports.size() == 1:
		var records: Array = published.reports[0].records
		_check(records.any(func(entry: Dictionary) -> bool: return entry.record_type == "visual" and entry.data.sense_tick == 0 and is_zero_approx(entry.device_configuration.parameters.scan_center)), "old event retains old camera config")
		_check(records.any(func(entry: Dictionary) -> bool: return entry.record_type == "visual" and entry.data.sense_tick > old_tick and is_equal_approx(entry.device_configuration.parameters.scan_center, 0.2)), "next sensing uses new camera config")
	f.view.queue_free()
	await (Engine.get_main_loop() as SceneTree).process_frame

func _sync_rejection_and_fault() -> void:
	for sync_mode: String in ["prepare", "activate"]:
		var f: Dictionary = _fixture(sync_mode)
		_check(not f.is_empty(), sync_mode + " fixture created")
		if f.is_empty(): continue
		_check(await _enter(f), sync_mode + " contact entered")
		var original: Dictionary = f.service.get_world_snapshot().to_snapshot()
		var tick: int = f.session.get_cycle_snapshot().simulation_tick
		_check(f.runtime.select_contact_target_at(Vector2(416, 96)) and f.runtime.submit_contact_text("调整扫描"), sync_mode + " proposal ready")
		var token: String = f.runtime.get_contact_ui_snapshot().proposal.token
		_check(not f.runtime.confirm_contact_proposal(token), sync_mode + " commit refused")
		_check(f.session.get_state_snapshot().phase == SessionPhase.Phase.CONTACT_PAUSED and f.session.get_cycle_snapshot().simulation_tick == tick and f.service.get_world_snapshot().to_snapshot() == original, sync_mode + " keeps authoritative world paused")
		if sync_mode == "prepare":
			_check(f.runtime.get_contact_ui_snapshot().fatal.is_empty() and f.runtime.keep_current(), "prepare rejection permits explicit keep")
		else:
			_check(f.runtime.get_contact_ui_snapshot().fatal == "SYNC_ACTIVATION_FAILED" and not f.runtime.keep_current(), "activation fault locks contact")
		f.view.queue_free()
		await (Engine.get_main_loop() as SceneTree).process_frame

func _main_scene_ui() -> void:
	var main: Node2D = load("res://scenes/main.tscn").instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	var runtime: GameRuntime = main.get("_runtime")
	_check(runtime != null, "main scene wires contact runtime")
	if runtime == null:
		main.queue_free()
		return
	runtime.auto_advance = false
	var view: RuntimeWorldView = main.get_node("World")
	view.get_player().global_position = Vector2(96, 300)
	_check(runtime.step_once(Vector2.ZERO, 1.0 / 60.0, true).get("ok") == true, "main scene enters contact")
	runtime.auto_advance = true
	main.call("_process", 0.0)
	runtime.auto_advance = false
	var panel: PanelContainer = main.get_node("UI/ContactPanel")
	_check(panel.visible, "contact UI visible while paused")
	var input: LineEdit = main.get_node("UI/ContactPanel/MarginContainer/VBox/PlayerText")
	var send: Button = main.get_node("UI/ContactPanel/MarginContainer/VBox/Buttons/Send")
	for index: int in 16:
		input.text = "现场记录 %d：" % index + "观察到的情况。".repeat(12)
		send.pressed.emit()
	_check(runtime.select_contact_target_at(Vector2(416, 96)), "main scene camera mark works")
	input.text = "请检查这台摄像头"
	send.pressed.emit()
	var info: RichTextLabel = main.get_node("UI/ContactPanel/MarginContainer/VBox/ContactInfo")
	_check(info.text.contains("scan_center") and info.text.contains("scan_half_angle") and not info.text.contains("contact-target-"), "UI displays full fields without internal handle")
	await (Engine.get_main_loop() as SceneTree).process_frame
	var keep: Button = main.get_node("UI/ContactPanel/MarginContainer/VBox/Buttons/Keep")
	var scroll: VScrollBar = info.get_v_scroll_bar()
	_check(scroll.max_value > info.size.y and scroll.value >= scroll.max_value - scroll.page - 1.0 and keep.get_global_rect().end.y <= panel.get_global_rect().end.y + 1.0, "long dialogue follows latest proposal while buttons stay visible")
	scroll.value = 0.0
	runtime.auto_advance = true
	main.call("_process", 0.0)
	runtime.auto_advance = false
	_check(is_zero_approx(scroll.value), "unchanged transcript preserves manual scroll position")
	(main.get_node("UI/ContactPanel/MarginContainer/VBox/Buttons/Confirm") as Button).pressed.emit()
	_check(not panel.visible and runtime.get_contact_ui_snapshot().open == false, "UI confirmation resumes and closes contact")
	main.queue_free()
	await (Engine.get_main_loop() as SceneTree).process_frame

func _reject_and_keep() -> void:
	var f: Dictionary = _fixture()
	_check(not f.is_empty(), "retry fixture created")
	if f.is_empty(): return
	_check(await _enter(f), "retry contact entered")
	var original: Dictionary = f.service.get_world_snapshot().to_snapshot()
	var tick: int = f.session.get_cycle_snapshot().simulation_tick
	_check(f.runtime.select_contact_target_at(Vector2(416, 96)), "retry target selected")
	var context: Dictionary = f.session.get_state_snapshot().active_request_context
	f.assistant.queue_response({"context": context, "status": "ok", "payload": {"kind": "MESSAGE", "text": "把它转向北面"}})
	_check(f.runtime.submit_contact_text("现场观察"), "text-only reply accepted")
	_check(f.service.get_world_snapshot().to_snapshot() == original, "prose did not alter world")
	var old_request_id: int = f.session.get_state_snapshot().active_request_context.request_id
	f.assistant.queue_response({"context": context, "status": "ok", "payload": {"kind": "PROPOSAL", "text": "越权", "action": {"type": "SetCameraScan", "target_ref": "other-target", "values": {"scan_speed": 2.0}}}})
	_check(not f.runtime.submit_contact_text("再试一次"), "invalid action rejected")
	_check(f.session.get_state_snapshot().phase == SessionPhase.Phase.CONTACT_PAUSED and f.session.get_cycle_snapshot().simulation_tick == tick, "invalid action stays paused")
	_check(f.service.get_world_snapshot().to_snapshot() == original and f.session.get_state_snapshot().active_request_context.request_id > old_request_id, "atomic rejection and new identity")
	var service_context: Dictionary = f.session.get_state_snapshot().active_request_context
	f.assistant.queue_response({"context": service_context, "status": "ok", "payload": {"kind": "PROPOSAL", "text": "数值越界", "action": {"type": "SetCameraScan", "target_ref": "contact-target-1", "values": {"scan_center": 99.0}}}})
	_check(f.runtime.submit_contact_text("试试大角度"), "well-formed but out-of-range proposal shown")
	var rejected_token: String = f.runtime.get_contact_ui_snapshot().proposal.token
	_check(not f.runtime.confirm_contact_proposal(rejected_token), "world service rejects invalid parameter")
	_check(f.session.get_state_snapshot().phase == SessionPhase.Phase.CONTACT_PAUSED and f.service.get_world_snapshot().to_snapshot() == original, "service rejection preserves pause and world")
	_check(f.runtime.get_contact_ui_snapshot().error == "CHANGE_REJECTED", "service error returned safely")
	_check(f.runtime.submit_contact_text("请给新建议"), "manual retry gives proposal")
	var old_token: String = f.runtime.get_contact_ui_snapshot().proposal.token
	_check(f.runtime.select_contact_target_at(Vector2(416, 96)) and not f.runtime.confirm_contact_proposal(old_token), "reselection invalidates token")
	_check(f.runtime.keep_current(), "explicit keep resumes action")
	_check(f.service.get_world_snapshot().to_snapshot() == original and f.session.get_cycle_snapshot().simulation_tick == tick, "keep preserves world and tick")
	f.view.queue_free()
	await (Engine.get_main_loop() as SceneTree).process_frame

func _check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		push_error("RUNTIME CONTACT TEST FAILED: " + label)
