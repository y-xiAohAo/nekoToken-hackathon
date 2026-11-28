extends RefCounted
class_name WorldFrame


var simulation_tick: int
var player_world_position: Vector2
var goal_complete: bool
var at_exit: bool
var world_revision: int


func _init(
	p_simulation_tick: int,
	p_player_world_position: Vector2,
	p_goal_complete: bool,
	p_at_exit: bool,
	p_world_revision: int = 0
) -> void:
	simulation_tick = p_simulation_tick
	player_world_position = p_player_world_position
	goal_complete = p_goal_complete
	at_exit = p_at_exit
	world_revision = p_world_revision


func snapshot() -> Dictionary:
	return {
		"simulation_tick": simulation_tick,
		"player_world_position": player_world_position,
		"goal_complete": goal_complete,
		"at_exit": at_exit,
		"world_revision": world_revision,
	}


func snapshot_copy() -> WorldFrame:
	return WorldFrame.new(simulation_tick, player_world_position, goal_complete, at_exit, world_revision)


static func from_snapshot(data: Dictionary) -> WorldFrame:
	if not DeviceRegistry.fields(data, ["simulation_tick", "player_world_position", "goal_complete", "at_exit", "world_revision"]):
		return null
	if typeof(data.simulation_tick) != TYPE_INT or data.simulation_tick < 0 or typeof(data.world_revision) != TYPE_INT or data.world_revision < 0:
		return null
	if not data.player_world_position is Vector2 or not data.player_world_position.is_finite() or typeof(data.goal_complete) != TYPE_BOOL or typeof(data.at_exit) != TYPE_BOOL:
		return null
	return WorldFrame.new(data.simulation_tick, data.player_world_position, data.goal_complete, data.at_exit, data.world_revision)
