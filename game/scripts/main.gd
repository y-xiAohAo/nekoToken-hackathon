extends Node2D

@onready var status_label: Label = $UI/StatusPanel/MarginContainer/StatusLabel
@onready var world_view: RuntimeWorldView = $World

var _session: GameSession
var _runtime: GameRuntime
var _service: WorldCommandService


func _ready() -> void:
	var world: WorldState = LevelTemplate.from_data(PrototypeConfig.level_data()).instantiate_world()
	if world == null or not world_view.build_from_world(world):
		push_error("Unable to build graybox world")
		return
	var adapter := SceneWorldSyncAdapter.new(world_view)
	_service = WorldCommandService.new(world, {}, adapter)
	_session = GameSession.new(PrototypeConfig.make_session_rules())
	_runtime = GameRuntime.new()
	add_child(_runtime)
	_runtime.configure(_service, _session, world_view, PrototypeConfig.movement_rules())
	status_label.text = "2042 GRAYBOX\nWASD move · E interact · Q cancel"
	print("FRAMEWORK_SHELL_READY")
	print("RUNTIME_GRAYBOX_READY")
	print("RUNTIME_INTERACTIONS_READY")


func _process(_delta: float) -> void:
	if _session == null or _runtime == null:
		return
	var tick: int = _session.get_cycle_snapshot().simulation_tick
	var phase: int = _session.get_state_snapshot().phase
	var interaction_text: String = "E near device/contact"
	var goals: Array[Dictionary] = []
	for entity: Dictionary in _service.get_world_snapshot().registry.to_snapshot():
		if entity.kind == "goal":
			goals.append(entity)
	if phase == SessionPhase.Phase.CONTACT_PAUSED:
		interaction_text = "Contact paused · E keep current"
	elif phase == SessionPhase.Phase.ROUND_END:
		interaction_text = "Round complete"
	elif not goals.is_empty() and goals.all(func(goal: Dictionary) -> bool: return goal.runtime_state.complete):
		interaction_text = "Goal complete · reach exit"
	else:
		for goal: Dictionary in goals:
			if goal.runtime_state.active:
				interaction_text = "Verification %d%%" % int(goal.runtime_state.progress * 100.0)
	status_label.text = "2042 GRAYBOX\nWASD move · E interact · Q cancel\nTick %d · Phase %d\n%s%s" % [tick, phase, interaction_text, "\nFAULT: " + _runtime.get_fault() if not _runtime.get_fault().is_empty() else ""]
