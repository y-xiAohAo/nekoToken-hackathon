extends Node2D

@onready var status_label: Label = $UI/StatusPanel/MarginContainer/StatusLabel
@onready var world_view: RuntimeWorldView = $World
@onready var contact_panel: PanelContainer = $UI/ContactPanel
@onready var contact_info: RichTextLabel = $UI/ContactPanel/MarginContainer/VBox/ContactInfo
@onready var player_text: LineEdit = $UI/ContactPanel/MarginContainer/VBox/PlayerText
@onready var send_button: Button = $UI/ContactPanel/MarginContainer/VBox/Buttons/Send
@onready var confirm_button: Button = $UI/ContactPanel/MarginContainer/VBox/Buttons/Confirm
@onready var change_button: Button = $UI/ContactPanel/MarginContainer/VBox/Buttons/Change
@onready var keep_button: Button = $UI/ContactPanel/MarginContainer/VBox/Buttons/Keep
@onready var reset_panel: PanelContainer = $UI/ResetPanel
@onready var reset_info: Label = $UI/ResetPanel/MarginContainer/VBox/ResetInfo
@onready var local_reset_button: Button = $UI/ResetPanel/MarginContainer/VBox/Buttons/LocalReset
@onready var decline_reset_button: Button = $UI/ResetPanel/MarginContainer/VBox/Buttons/DeclineReset
@onready var round_panel: PanelContainer = $UI/RoundPanel
@onready var round_info: Label = $UI/RoundPanel/MarginContainer/VBox/RoundInfo
@onready var advance_round_button: Button = $UI/RoundPanel/MarginContainer/VBox/AdvanceRound

var _session: GameSession
var _runtime: GameRuntime
var _service: WorldCommandService
var _sensing: RuntimeSensingCoordinator
var _contact: ContactSessionController
var _reset: ResetCoordinator


func _ready() -> void:
	var world: WorldState = LevelTemplate.from_data(PrototypeConfig.level_data()).instantiate_world()
	if world == null or not world_view.build_from_world(world):
		push_error("Unable to build graybox world")
		return
	var adapter := SceneWorldSyncAdapter.new(world_view)
	_service = WorldCommandService.new(world, PrototypeConfig.combined_policy(), adapter)
	_session = GameSession.new(PrototypeConfig.make_session_rules())
	_runtime = GameRuntime.new()
	_runtime.auto_advance = false
	add_child(_runtime)
	_runtime.configure(_service, _session, world_view, PrototypeConfig.movement_rules())
	_contact = ContactSessionController.new(_session, _service, world_view,
		SimulatedPlayerAssistant.new(PrototypeConfig.simulated_assistant_scan(), PrototypeConfig.simulated_assistant_route()),
		PrototypeConfig.player_assistant_route_rules())
	if not _runtime.configure_contact(_contact):
		push_error("Unable to configure contact")
		return
	send_button.pressed.connect(_send_contact_text)
	player_text.text_submitted.connect(_submit_contact_text)
	confirm_button.pressed.connect(_confirm_contact)
	change_button.pressed.connect(_change_proposal)
	keep_button.pressed.connect(_keep_current)
	var state: Dictionary = _session.get_state_snapshot()
	var cycle: Dictionary = _session.get_cycle_snapshot()
	if cycle.simulation_tick != 0 or state.phase != SessionPhase.Phase.ACTION:
		status_label.text = "2042 GRAYBOX\nSensing clock initialization failed"
		push_error("Unable to initialize sensing clock")
		return
	_sensing = RuntimeSensingCoordinator.new()
	var context: Dictionary = {"round_id": state.round_id, "branch_id": state.branch_id,
		"guess_cycle_id": state.guess_cycle_id, "report_cycle_id": _session.period_for_event_tick(0) + 1, "sense_tick": 0}
	if not _sensing.initialize_round(_service.get_world_snapshot(), context, _session.get_ticks_per_report_period(), PrototypeConfig.system_dispatch_policy()) or not _runtime.configure_sensing(_sensing):
		status_label.text = "2042 GRAYBOX\nSensing initialization failed"
		push_error("Unable to initialize sensing")
		return
	var agent_rules: Dictionary = PrototypeConfig.system_agent_rules()
	agent_rules["dispatch_policy"] = PrototypeConfig.system_dispatch_policy()
	var history := SystemAgentHistory.new()
	if not _runtime.configure_agent(SimulatedAgentGateway.new(PrototypeConfig.simulated_system_script(), true), history, agent_rules):
		push_error("Unable to configure simulated system agent")
		return
	_reset = ResetCoordinator.new(_service, _session, _sensing, RunState.new(world), history, _contact)
	local_reset_button.pressed.connect(_choose_local_reset)
	decline_reset_button.pressed.connect(_decline_local_reset)
	advance_round_button.pressed.connect(_advance_round)
	if not _runtime.configure_reset(_reset) or not _runtime.capture_initial_checkpoint():
		push_error("Unable to save initial cycle checkpoint")
		return
	_runtime.auto_advance = true
	status_label.text = "2042 GRAYBOX\nWASD move · E interact · Q cancel"
	print("FRAMEWORK_SHELL_READY")
	print("RUNTIME_GRAYBOX_READY")
	print("RUNTIME_INTERACTIONS_READY")
	print("RUNTIME_SENSING_READY")
	print("RUNTIME_CONTACT_READY")
	print("RUNTIME_ROBOT_CONTACT_READY")
	print("RUNTIME_AGENT_READY")


func _process(_delta: float) -> void:
	if _session == null or _runtime == null or not _runtime.auto_advance:
		return
	var tick: int = _session.get_cycle_snapshot().simulation_tick
	var phase: int = _session.get_state_snapshot().phase
	var interaction_text: String = "E near device/contact"
	var goals: Array[Dictionary] = []
	for entity: Dictionary in _service.get_world_snapshot().registry.to_snapshot():
		if entity.kind == "goal":
			goals.append(entity)
	if phase == SessionPhase.Phase.CONTACT_PAUSED:
		interaction_text = "Contact paused · select camera or robot, chat, confirm or keep current"
	elif phase == SessionPhase.Phase.ROUND_END:
		interaction_text = "Round complete"
	elif not goals.is_empty() and goals.all(func(goal: Dictionary) -> bool: return goal.runtime_state.complete):
		interaction_text = "Goal complete · reach exit"
	else:
		for goal: Dictionary in goals:
			if goal.runtime_state.active:
				interaction_text = "Verification %d%%" % int(goal.runtime_state.progress * 100.0)
	status_label.text = "2042 GRAYBOX\nWASD move · E interact · Q cancel\nTick %d · Phase %d\n%s%s" % [tick, phase, interaction_text, "\nFAULT: " + _runtime.get_fault() if not _runtime.get_fault().is_empty() else ""]
	_refresh_contact_ui()
	_refresh_reset_ui()
	_refresh_round_ui()


func _choose_local_reset() -> void:
	if _runtime != null:
		_runtime.choose_local_reset()
	_refresh_reset_ui()


func _decline_local_reset() -> void:
	if _runtime != null:
		_runtime.decline_local_reset()
	_refresh_reset_ui()


func _refresh_reset_ui() -> void:
	var open: bool = _session.get_state_snapshot().phase == SessionPhase.Phase.RESET_CHOICE
	reset_panel.visible = open
	if not open:
		return
	var remaining: int = _runtime.get_run_snapshot().get("remaining_local_resets", 0)
	reset_info.text = "定位命中。剩余局部回退：%d" % remaining
	local_reset_button.disabled = remaining <= 0 or not _runtime.get_fault().is_empty()
	decline_reset_button.disabled = not _runtime.get_fault().is_empty()


func _advance_round() -> void:
	if _runtime != null:
		_runtime.advance_round()
	_refresh_round_ui()


func _refresh_round_ui() -> void:
	var phase: int = _session.get_state_snapshot().phase
	round_panel.visible = phase in [SessionPhase.Phase.ROUND_END, SessionPhase.Phase.ROUND_SETUP_PAUSED]
	if not round_panel.visible:
		return
	var run: Dictionary = _runtime.get_run_snapshot()
	if phase == SessionPhase.Phase.ROUND_SETUP_PAUSED:
		round_info.text = "正在校验下一轮配置。" if _runtime.get_reset_error().is_empty() else "轮间配置未提交：" + _runtime.get_reset_error()
		advance_round_button.disabled = true
		return
	var finished: bool = run.get("round_results", []).size() >= run.get("max_rounds", 4)
	round_info.text = "四轮已结算。" if finished else "本轮结束，可进入下一轮。"
	advance_round_button.disabled = finished or not _runtime.get_fault().is_empty()


func _unhandled_input(event: InputEvent) -> void:
	if _runtime == null or not event is InputEventMouseButton:
		return
	if event.button_index == MOUSE_BUTTON_LEFT and event.pressed and _runtime.get_contact_ui_snapshot().get("open") == true:
		if _runtime.select_contact_target_at(event.position):
			get_viewport().set_input_as_handled()
			_refresh_contact_ui()


func _send_contact_text() -> void:
	_submit_contact_text(player_text.text)


func _submit_contact_text(message: String) -> void:
	if _runtime != null and _runtime.submit_contact_text(message):
		player_text.clear()
	_refresh_contact_ui()


func _confirm_contact() -> void:
	if _runtime == null:
		return
	var proposal: Dictionary = _runtime.get_contact_ui_snapshot().get("proposal", {})
	_runtime.confirm_contact_proposal(str(proposal.get("token", "")))
	_refresh_contact_ui()


func _change_proposal() -> void:
	if _runtime != null:
		_runtime.discard_contact_proposal()
	_refresh_contact_ui()


func _keep_current() -> void:
	if _runtime != null:
		_runtime.keep_current()
	_refresh_contact_ui()


func _refresh_contact_ui() -> void:
	var snapshot: Dictionary = _runtime.get_contact_ui_snapshot()
	contact_panel.visible = snapshot.get("open") == true
	if not contact_panel.visible:
		return
	var lines: Array[String] = []
	if not snapshot.selected:
		lines.append("点击画面中的摄像头或机器人以标记目标。")
	elif snapshot.selected_kind == "robot":
		lines.append("已标记一台机器人（本次联络有效）。")
	else:
		lines.append("已标记一台摄像头（本次联络有效）。")
	for line: Dictionary in snapshot.conversation:
		lines.append(("你：" if line.role == "player" else "助手：") + line.text)
	var proposal: Dictionary = snapshot.proposal
	if not proposal.is_empty():
		if proposal.type == "SetPatrolRoute":
			lines.append("待确认：重设已标记机器人的巡逻路线")
			lines.append("  驻守当前段终点" if proposal.values.steps.is_empty() else "  方向：" + " → ".join(proposal.values.steps))
			lines.append("  完整路径已在场景中高亮。")
		else:
			lines.append("待确认：调整已标记摄像头")
			for field: String in PlayerAssistantContract.CAMERA_FIELDS:
				if proposal.values.has(field):
					lines.append("  %s = %s" % [field, str(proposal.values[field])])
	if snapshot.route_locked:
		lines.append("路线尝试已用尽；请明确选择保持现状结束联络。")
	if not snapshot.error.is_empty():
		lines.append("未提交：" + snapshot.error)
	if not snapshot.fatal.is_empty():
		lines.append("同步故障：请停止本轮")
	var next_text: String = "\n".join(lines)
	if contact_info.text != next_text:
		contact_info.text = next_text
	var locked: bool = snapshot.route_locked or not snapshot.fatal.is_empty()
	player_text.editable = not locked
	send_button.disabled = locked
	confirm_button.disabled = proposal.is_empty() or locked
	change_button.disabled = proposal.is_empty() or locked
	keep_button.disabled = not snapshot.fatal.is_empty()
