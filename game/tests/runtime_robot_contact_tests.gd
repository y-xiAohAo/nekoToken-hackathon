extends RefCounted
class_name RuntimeRobotContactTests

var passed: int = 0
var failed: int = 0

class RejectPrepare extends SceneWorldSyncAdapter:
	func prepare(_previous: Dictionary, _candidate: Dictionary, _changes: Dictionary) -> Dictionary:
		return {"ok": false, "errors": [{"code": "INJECTED_PREPARE"}]}

class RejectActivate extends SceneWorldSyncAdapter:
	func activate(prepared: Dictionary) -> bool:
		for node: Node in prepared.get("changed", {}).values():
			node.queue_free()
		return false


func run() -> Dictionary:
	_expansion_and_anchor()
	await _target_and_preview()
	await _commit_route_and_report()
	await _mid_segment_hold_and_keep()
	await _route_rejections_and_lock()
	await _stale_reselection_and_faults()
	await _main_scene_robot_ui()
	return {"passed": passed, "failed": failed}


func _expansion_and_anchor() -> void:
	var world: WorldState = LevelTemplate.from_data(PrototypeConfig.level_data()).instantiate_world()
	_check(world != null, "robot route world fixture")
	if world == null:
		return
	if not world.has_method("expand_patrol_path"):
		_check(false, "direction expansion API exists")
		return
	var robot_id: int = _robot_id(world)
	_check(world.expand_patrol_path(robot_id, ["E", "N"]) == [[4, 3], [5, 3], [5, 2]], "grid anchor expands cardinal steps")
	_check(world.expand_patrol_path(robot_id, []) == [[4, 3]], "empty directions expand to single-point hold")
	_check(world.expand_patrol_path(robot_id, ["E", "W"]) == [[4, 3], [5, 3], [4, 3]], "repeated cells remain legal path data")
	_check(world.expand_patrol_path(robot_id, ["NW"]).is_empty(), "invalid direction returns no path")
	var robot: Dictionary = world.registry.get_entity(robot_id)
	robot.runtime_state.progress = 0.5
	robot.runtime_state.position = DeviceRegistry.pair(world.cell_to_world(Vector2i(4, 3)).lerp(world.cell_to_world(Vector2i(5, 3)), 0.5))
	world.registry._put(robot)
	var before: Dictionary = world.to_snapshot()
	_check(world.expand_patrol_path(robot_id, ["N"]) == [[5, 3], [5, 2]], "mid-segment expansion starts at segment endpoint")
	_check(world.to_snapshot() == before, "expansion never mutates world")


func _target_and_preview() -> void:
	var world: WorldState = LevelTemplate.from_data(PrototypeConfig.level_data()).instantiate_world()
	var view := RuntimeWorldView.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(view)
	if world == null or not view.build_from_world(world):
		_check(false, "robot target scene fixture")
		view.queue_free()
		return
	if not view.has_method("contact_target_at_screen_position") or not view.has_method("set_contact_route_preview"):
		_check(false, "generic target and preview APIs exist")
		view.queue_free()
		await (Engine.get_main_loop() as SceneTree).process_frame
		return
	var robot_id: int = _robot_id(world)
	var camera_id: int = 1
	_check(view.is_contact_target_displayed(robot_id), "displayed robot is a contact target")
	_check(view.contact_target_at_screen_position(Vector2(288, 224)) == robot_id, "screen click hits robot")
	_check(view.contact_target_at_screen_position(Vector2(416, 96)) == camera_id, "screen click still hits camera")
	_check(view.contact_target_at_screen_position(Vector2(700, 500)) == 0, "empty screen click has no target")
	view.mark_contact_target(robot_id)
	var robot: RobotController = view.get_entity_node(robot_id)
	var robot_selection: Line2D = robot.get("selection")
	_check(robot_selection != null and robot_selection.visible, "robot selection marker is visible")
	view.set_contact_route_preview([[4, 3]])
	var preview: Node2D = view.get("_route_preview")
	_check(view.get("_route_preview_cells") == [[4, 3]] and preview != null and preview.visible and preview.get_child_count() > 0, "single-point hold has visible preview")
	view.set_contact_route_preview([[4, 3], [5, 3], [5, 2]])
	_check(view.get("_route_preview_cells").size() == 3 and preview.get_child_count() >= 4, "multi-cell route shows line and waypoint markers")
	view.mark_contact_target(camera_id)
	_check(not robot_selection.visible and (view.get_entity_node(camera_id) as DeviceView).selection.visible, "reselection moves highlight to camera")
	view.set_contact_route_preview([])
	_check(view.get("_route_preview_cells").is_empty() and not preview.visible, "clearing route hides preview")
	_check(view.camera_at_screen_position(Vector2(416, 96)) == camera_id and view.is_camera_displayed(camera_id), "7A camera wrappers remain compatible")
	view.queue_free()
	await (Engine.get_main_loop() as SceneTree).process_frame


func _main_scene_robot_ui() -> void:
	var main: Node2D = load("res://scenes/main.tscn").instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	var runtime: GameRuntime = main.get("_runtime")
	_check(runtime != null, "main scene robot contact wiring")
	if runtime == null:
		main.queue_free()
		return
	runtime.auto_advance = false
	var view: RuntimeWorldView = main.get_node("World")
	view.get_player().global_position = Vector2(96, 300)
	_check(runtime.step_once(Vector2.ZERO, 1.0 / 60.0, true).get("ok") == true, "main scene enters robot-capable contact")
	var robot: RobotController = view.get_entity_node(_robot_id(runtime._world_service.get_world_snapshot()))
	_check(runtime.select_contact_target_at(robot.get_global_transform_with_canvas() * Vector2.ZERO), "main scene marks robot")
	var input: LineEdit = main.get_node("UI/ContactPanel/MarginContainer/VBox/PlayerText")
	var send: Button = main.get_node("UI/ContactPanel/MarginContainer/VBox/Buttons/Send")
	input.text = "请调整机器人路线"
	send.pressed.emit()
	var info: RichTextLabel = main.get_node("UI/ContactPanel/MarginContainer/VBox/ContactInfo")
	_check(info.text.contains("机器人") and info.text.contains("E") and info.text.contains("完整路径") and not info.text.contains("contact-target-"), "main UI shows route without opaque ref")
	_check(not view.get("_route_preview_cells").is_empty(), "main scene displays full route preview")
	var confirm: Button = main.get_node("UI/ContactPanel/MarginContainer/VBox/Buttons/Confirm")
	_check(not confirm.disabled, "main route confirmation enabled")
	confirm.pressed.emit()
	_check(not (main.get_node("UI/ContactPanel") as PanelContainer).visible and runtime.get_contact_ui_snapshot().open == false, "main route confirmation closes contact")
	main.queue_free()
	await (Engine.get_main_loop() as SceneTree).process_frame


func _route_fixture(route_steps: Array = ["E", "N"], sync_mode: String = "", moving: bool = false) -> Dictionary:
	var level: Dictionary = PrototypeConfig.level_data()
	level.player_spawn = [96.0, 300.0]
	if not moving:
		level.initial_entities[1].patrol_path = [[4, 3]]
	var world: WorldState = LevelTemplate.from_data(level).instantiate_world()
	var view := RuntimeWorldView.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(view)
	if world == null or not view.build_from_world(world):
		view.queue_free()
		return {}
	var adapter: SceneWorldSyncAdapter = SceneWorldSyncAdapter.new(view)
	if sync_mode == "prepare":
		adapter = RejectPrepare.new(view)
	elif sync_mode == "activate":
		adapter = RejectActivate.new(view)
	var service := WorldCommandService.new(world, PrototypeConfig.player_assistant_policy(), adapter)
	var session := GameSession.new(SessionRules.new(30, 4))
	var assistant := SimulatedPlayerAssistant.new(PrototypeConfig.simulated_assistant_scan(), route_steps)
	var contact := ContactSessionController.new(session, service, view, assistant, PrototypeConfig.player_assistant_route_rules())
	var runtime := GameRuntime.new()
	view.add_child(runtime)
	runtime.auto_advance = false
	runtime.configure(service, session, view, PrototypeConfig.movement_rules())
	if not runtime.configure_contact(contact):
		view.queue_free()
		return {}
	var sensing := RuntimeSensingCoordinator.new()
	var state: Dictionary = session.get_state_snapshot()
	var context: Dictionary = {"round_id": state.round_id, "branch_id": state.branch_id, "guess_cycle_id": state.guess_cycle_id,
		"report_cycle_id": session.period_for_event_tick(0) + 1, "sense_tick": 0}
	if not sensing.initialize_round(service.get_world_snapshot(), context, session.get_ticks_per_report_period()) or not runtime.configure_sensing(sensing):
		view.queue_free()
		return {}
	return {"view": view, "service": service, "session": session, "runtime": runtime, "assistant": assistant,
		"contact": contact, "sensing": sensing, "robot_id": _robot_id(world)}


func _enter_contact(f: Dictionary) -> bool:
	await (Engine.get_main_loop() as SceneTree).physics_frame
	return f.runtime.step_once(Vector2.ZERO, 1.0 / 60.0, true).get("ok") == true \
		and f.session.get_state_snapshot().phase == SessionPhase.Phase.CONTACT_PAUSED


func _select_robot(f: Dictionary) -> bool:
	return f.runtime.select_contact_target_at(Vector2(288, 224))


func _queue_route(f: Dictionary, steps: Array) -> void:
	var context: Dictionary = f.session.get_state_snapshot().active_request_context
	f.assistant.queue_response({"context": context, "status": "ok", "payload": {"kind": "PROPOSAL", "text": "路线提案", "action": {
		"type": "SetPatrolRoute", "target_ref": f.contact.get("_selected_ref"), "values": {"steps": steps.duplicate(true)}}}})


func _commit_route_and_report() -> void:
	var f: Dictionary = _route_fixture()
	_check(not f.is_empty(), "route commit fixture")
	if f.is_empty(): return
	_check(await _enter_contact(f), "route contact entered")
	var original: Dictionary = f.service.get_world_snapshot().to_snapshot()
	var old_tick: int = f.session.get_cycle_snapshot().simulation_tick
	var old_view: Dictionary = f.sensing.get_system_view()
	_check(_select_robot(f), "runtime selects displayed robot")
	_check(f.runtime.submit_contact_text("请调整巡逻路线"), "bounded route proposal accepted")
	var proposal: Dictionary = f.runtime.get_contact_ui_snapshot().proposal
	_check(proposal.get("type") == "SetPatrolRoute" and proposal.get("preview_cells") == [[4, 3], [5, 3], [5, 2]], "player receives full expanded route")
	_check(f.service.get_world_snapshot().to_snapshot() == original and f.session.get_cycle_snapshot().simulation_tick == old_tick, "route preview does not mutate world")
	_check(f.runtime.confirm_contact_proposal(proposal.token), "route confirmation commits")
	var changed: WorldState = f.service.get_world_snapshot()
	_check(changed.registry.get_entity(f.robot_id).patrol_path == proposal.preview_cells and changed.world_revision == original.world_revision + 1, "one command and revision updates route")
	_check(changed.registry.get_entity(f.robot_id).runtime_state.position == original.entities[1].runtime_state.position and f.session.get_state_snapshot().phase == SessionPhase.Phase.ACTION, "deployment resumes without teleport")
	_check(f.sensing.get_system_view() == old_view, "route config is not revealed before report boundary")
	while f.session.get_cycle_snapshot().simulation_tick < 30:
		f.runtime.step_once(Vector2.ZERO, 1.0 / 60.0)
	var published: Dictionary = f.sensing.get_system_view()
	_check(not published.world.robots.is_empty() and published.world.robots[0].patrol_path == proposal.preview_cells, "normal report publishes new robot route")
	_check(published.reports[0].records.any(func(entry: Dictionary) -> bool:
		return entry.record_type == "visual" and entry.data.sense_tick == 0 and entry.device_configuration.get("patrol_path", []) == [[4, 3]]), "tick zero report retains old route")
	f.view.queue_free()
	await (Engine.get_main_loop() as SceneTree).process_frame


func _mid_segment_hold_and_keep() -> void:
	var f: Dictionary = _route_fixture([], "", true)
	_check(not f.is_empty(), "mid-segment fixture")
	if f.is_empty(): return
	for _i: int in 10:
		f.runtime.step_once(Vector2.ZERO, 1.0 / 60.0)
	_check(await _enter_contact(f) and _select_robot(f), "mid-segment robot selected")
	var before: Dictionary = f.service.get_world_snapshot().registry.get_entity(f.robot_id).duplicate(true)
	_check(f.runtime.submit_contact_text("请驻守"), "hold proposal accepted")
	var proposal: Dictionary = f.runtime.get_contact_ui_snapshot().proposal
	_check(proposal.preview_cells == [[5, 3]], "hold anchors at unfinished segment endpoint")
	_check(f.runtime.confirm_contact_proposal(proposal.token), "hold commits")
	var held: Dictionary = f.service.get_world_snapshot().registry.get_entity(f.robot_id)
	_check(held.patrol_path == [[5, 3]] and held.runtime_state.transition.to_cell == [5, 3] and held.runtime_state.position == before.runtime_state.position, "hold preserves current transition and position")
	for _i: int in 70:
		f.runtime.step_once(Vector2.ZERO, 1.0 / 60.0)
	held = f.service.get_world_snapshot().registry.get_entity(f.robot_id)
	_check(held.runtime_state.transition.is_empty() and held.runtime_state.position == [352.0, 224.0], "robot finishes segment then holds")
	f.view.queue_free()
	await (Engine.get_main_loop() as SceneTree).process_frame
	f = _route_fixture(["E"])
	_check(await _enter_contact(f) and _select_robot(f), "keep fixture entered")
	var old_path: Array = f.service.get_world_snapshot().registry.get_entity(f.robot_id).patrol_path.duplicate(true)
	var old_revision: int = f.service.get_world_snapshot().world_revision
	_check(f.runtime.keep_current(), "explicit keep succeeds")
	_check(f.service.get_world_snapshot().registry.get_entity(f.robot_id).patrol_path == old_path and f.service.get_world_snapshot().world_revision == old_revision, "keep differs from hold and preserves route")
	f.view.queue_free()
	await (Engine.get_main_loop() as SceneTree).process_frame


func _route_rejections_and_lock() -> void:
	var f: Dictionary = _route_fixture()
	_check(await _enter_contact(f) and _select_robot(f), "rejection fixture entered")
	if f.is_empty(): return
	var original: Dictionary = f.service.get_world_snapshot().to_snapshot()
	_queue_route(f, ["NW"])
	_check(not f.runtime.submit_contact_text("非法方向") and f.runtime.get_contact_ui_snapshot().route_attempts_remaining == 2, "DTO rejection does not consume route attempt")
	_queue_route(f, ["N"])
	_check(not f.runtime.submit_contact_text("穿墙路线"), "first invalid world route rejected")
	_check(f.runtime.get_contact_ui_snapshot().error == "ROUTE_REJECTED" and f.runtime.get_contact_ui_snapshot().route_attempts_remaining == 1, "safe route receipt and remaining attempt")
	_check(f.service.get_world_snapshot().to_snapshot() == original and f.session.get_state_snapshot().phase == SessionPhase.Phase.CONTACT_PAUSED, "first route rejection is atomic")
	_queue_route(f, ["N"])
	_check(not f.runtime.submit_contact_text("再次穿墙"), "second invalid world route rejected")
	var locked: Dictionary = f.runtime.get_contact_ui_snapshot()
	_check(locked.route_locked and locked.route_attempts_remaining == 0 and locked.error == "ROUTE_REJECTED", "route attempts exhaust into locked tool")
	_check(not f.runtime.submit_contact_text("继续") and not _select_robot(f), "locked session rejects chat and target changes")
	_check(f.runtime.keep_current() and f.session.get_state_snapshot().phase == SessionPhase.Phase.ACTION, "only explicit keep exits locked route session")
	_check(f.service.get_world_snapshot().to_snapshot() == original, "route lock never auto-applies or changes world")
	var receipt_text: String = JSON.stringify(f.contact.get("_receipts"))
	_check(not receipt_text.contains("cell") and not receipt_text.contains("index") and not receipt_text.contains("path"), "route receipts contain no spatial oracle")
	f.view.queue_free()
	await (Engine.get_main_loop() as SceneTree).process_frame


func _stale_reselection_and_faults() -> void:
	var f: Dictionary = _route_fixture()
	_check(await _enter_contact(f) and _select_robot(f) and f.runtime.submit_contact_text("路线"), "stale proposal prepared")
	if f.is_empty(): return
	var token: String = f.runtime.get_contact_ui_snapshot().proposal.token
	f.contact.set("_pending_revision", f.contact.get("_pending_revision") + 1)
	_check(not f.runtime.confirm_contact_proposal(token) and f.runtime.get_contact_ui_snapshot().error == "STALE_PROPOSAL", "stale revision invalidates proposal")
	_check(f.runtime.submit_contact_text("新路线"), "replacement route after stale rejection")
	token = f.runtime.get_contact_ui_snapshot().proposal.token
	_check(f.runtime.select_contact_target_at(Vector2(416, 96)) and not f.runtime.confirm_contact_proposal(token), "cross-kind reselection invalidates route token")
	_check(f.view.get("_route_preview_cells").is_empty(), "reselection clears route preview")
	f.view.queue_free()
	await (Engine.get_main_loop() as SceneTree).process_frame
	for mode: String in ["prepare", "activate"]:
		f = _route_fixture(["E", "N"], mode)
		_check(await _enter_contact(f) and _select_robot(f) and f.runtime.submit_contact_text("路线"), mode + " route prepared")
		var original: Dictionary = f.service.get_world_snapshot().to_snapshot()
		token = f.runtime.get_contact_ui_snapshot().proposal.token
		_check(not f.runtime.confirm_contact_proposal(token), mode + " route commit refused")
		_check(f.service.get_world_snapshot().to_snapshot() == original and f.session.get_state_snapshot().phase == SessionPhase.Phase.CONTACT_PAUSED, mode + " route failure is atomic")
		if mode == "prepare":
			_check(f.runtime.get_contact_ui_snapshot().error == "CHANGE_REJECTED" and f.runtime.keep_current(), "prepare failure permits explicit keep")
		else:
			_check(f.runtime.get_contact_ui_snapshot().fatal == "SYNC_ACTIVATION_FAILED" and not f.runtime.keep_current(), "activation failure locks keep")
		f.view.queue_free()
		await (Engine.get_main_loop() as SceneTree).process_frame
	f = _route_fixture()
	_check(await _enter_contact(f) and _select_robot(f), "hidden player route fixture")
	f.service._world.player_position = Vector2(320, 224)
	_check(f.runtime.submit_contact_text("路线"), "hidden player on route does not change proposal")
	_check(f.runtime.confirm_contact_proposal(f.runtime.get_contact_ui_snapshot().proposal.token), "hidden player on route does not reject commit")
	_check(not PrototypeConfig.player_assistant_policy()[AgentProtocol.PLAYER_ASSISTANT].has("obstacle_protection_radius"), "assistant policy has no system player exclusion zone")
	f.view.queue_free()
	await (Engine.get_main_loop() as SceneTree).process_frame


func _robot_id(world: WorldState) -> int:
	for entity: Dictionary in world.registry.to_snapshot():
		if entity.kind == "robot":
			return entity.id
	return 0


func _check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		push_error("RUNTIME ROBOT CONTACT TEST FAILED: " + label)
