extends RefCounted
class_name WorldFrame


var simulation_tick: int
var player_world_position: Vector2
var goal_complete: bool
var at_exit: bool


func _init(
	p_simulation_tick: int,
	p_player_world_position: Vector2,
	p_goal_complete: bool,
	p_at_exit: bool
) -> void:
	simulation_tick = p_simulation_tick
	player_world_position = p_player_world_position
	goal_complete = p_goal_complete
	at_exit = p_at_exit


func snapshot() -> Dictionary:
	return {
		"simulation_tick": simulation_tick,
		"player_world_position": player_world_position,
		"goal_complete": goal_complete,
		"at_exit": at_exit,
	}


func snapshot_copy() -> WorldFrame:
	return WorldFrame.new(simulation_tick, player_world_position, goal_complete, at_exit)
