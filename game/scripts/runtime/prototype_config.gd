extends RefCounted
class_name PrototypeConfig
## Graybox fixture only. These values are not settled gameplay parameters.


static func movement_rules() -> Dictionary:
	return {"max_speed": 180.0, "acceleration": 900.0, "deceleration": 1200.0, "interaction_distance": 56.0, "goal_duration": 2.0}


static func make_session_rules() -> SessionRules:
	# Prototype: two 30-tick reports make one observable guess cycle.
	return SessionRules.new(30, 2)


static func location_constraints() -> Dictionary:
	return {"shape": "rectangle", "max_width": 2, "max_height": 2, "max_cells": 4}


static func system_agent_rules() -> Dictionary:
	return {"location_constraints": location_constraints(), "max_dispatch_attempts": 2}


static func simulated_system_script() -> Dictionary:
	return {"location": {"shape": "rectangle", "origin_cell": [10, 1], "size": [1, 1]},
		"dispatch": {"mode": "APPLY", "commands": [{"type": "MoveObstacle", "obstacle_id": 1, "anchor_cell": [8, 2]}]}}


static func system_dispatch_policy() -> Dictionary:
	var cells: Array = []
	var terrain: Array = level_data().terrain
	for y: int in terrain.size():
		for x: int in terrain[y].size():
			if terrain[y][x] == "FLOOR":
				cells.append([x, y])
	return {"commands": {"AddDevice": ["camera", "robot", "pressure_plate"],
		"RemoveDevice": ["camera", "robot", "pressure_plate"],
		"MoveDevice": ["camera", "pressure_plate"],
		"SetDeviceParameter": ["camera"], "SetCameraScanState": ["camera"],
		"SetPatrolPath": ["robot"], "MoveObstacle": ["obstacle"]},
		"parameters": {"camera": ["scan_center", "scan_half_angle"]},
		"max_commands": 2, "allowed_cells": cells,
		"device_limits": {"camera": 2, "robot": 2, "pressure_plate": 2},
		"obstacle_protection_radius": 1, "max_dispatch_attempts": 2}


static func combined_policy() -> Dictionary:
	return {AgentProtocol.SYSTEM_AGENT: system_dispatch_policy()}


static func device_rules() -> Dictionary:
	return {
		"parameter_ranges": {
			"camera": {"view_radius": [1.0, 1000.0], "fov_angle": [0.1, TAU], "scan_center": [-PI, PI], "scan_half_angle": [0.0, PI], "scan_speed": [0.0, TAU]},
			"robot": {"view_radius": [1.0, 1000.0], "move_speed": [1.0, 400.0]},
		},
		"camera_per_anchor": 1,
	}


static func level_data() -> Dictionary:
	return {
		"template_key": "graybox_fixture", "grid_size": [12, 8], "cell_size": 64.0, "origin": [0.0, 0.0],
		"terrain": [
			["WALL", "WALL", "WALL", "WALL", "WALL", "WALL", "WALL", "WALL", "WALL", "WALL", "WALL", "WALL"],
			["WALL", "FLOOR", "FLOOR", "FLOOR", "FLOOR", "FLOOR", "FLOOR", "FLOOR", "FLOOR", "FLOOR", "FLOOR", "WALL"],
			["WALL", "FLOOR", "FLOOR", "WALL", "WALL", "FLOOR", "FLOOR", "FLOOR", "FLOOR", "FLOOR", "FLOOR", "WALL"],
			["WALL", "FLOOR", "FLOOR", "FLOOR", "FLOOR", "FLOOR", "FLOOR", "FLOOR", "FLOOR", "FLOOR", "FLOOR", "WALL"],
			["WALL", "FLOOR", "FLOOR", "FLOOR", "FLOOR", "FLOOR", "FLOOR", "WALL", "WALL", "FLOOR", "FLOOR", "WALL"],
			["WALL", "FLOOR", "FLOOR", "FLOOR", "FLOOR", "FLOOR", "FLOOR", "FLOOR", "FLOOR", "FLOOR", "FLOOR", "WALL"],
			["WALL", "FLOOR", "FLOOR", "FLOOR", "FLOOR", "FLOOR", "FLOOR", "FLOOR", "FLOOR", "FLOOR", "FLOOR", "WALL"],
			["WALL", "WALL", "WALL", "WALL", "WALL", "WALL", "WALL", "WALL", "WALL", "WALL", "WALL", "WALL"],
		],
		"player_spawn": [96.0, 96.0], "device_rules": device_rules(),
		"obstacle_templates": [{"template_id": "house_2x2", "footprint": [[0, 0], [1, 0], [0, 1], [1, 1]],
			"blocks_movement": true, "blocks_vision": true, "scene_path": "res://scenes/runtime/obstacle_view.tscn"}],
		"initial_obstacles": [{"template_id": "house_2x2", "anchor_cell": [7, 2]}],
		"initial_entities": [
			{"kind": "camera", "cell": [6, 1], "parameters": {"enabled": true, "view_radius": 320.0, "fov_angle": 1.2, "scan_center": 0.0, "scan_half_angle": 0.8, "scan_speed": 1.0}},
			{"kind": "robot", "cell": [4, 3], "parameters": {"view_radius": 320.0, "move_speed": 60.0}, "patrol_path": [[4, 3], [5, 3], [6, 3]]},
			{"kind": "pressure_plate", "cell": [3, 3], "parameters": {}},
			{"kind": "goal", "cell": [9, 5], "parameters": {}},
			{"kind": "contact", "cell": [1, 5], "parameters": {}},
			{"kind": "exit", "cell": [10, 5], "parameters": {}},
		],
	}
