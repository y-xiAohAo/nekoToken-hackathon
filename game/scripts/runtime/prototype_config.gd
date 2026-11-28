extends RefCounted
class_name PrototypeConfig
## Graybox fixture only. These values are not settled gameplay parameters.


static func movement_rules() -> Dictionary:
	return {"max_speed": 180.0, "acceleration": 900.0, "deceleration": 1200.0, "interaction_distance": 56.0, "goal_duration": 2.0}


static func make_session_rules() -> SessionRules:
	# Keep the motion fixture interactive: real guessing and recovery belong to later modules.
	return SessionRules.new(30, 1000000)


static func device_rules() -> Dictionary:
	return {
		"parameter_ranges": {
			"camera": {"view_radius": [1.0, 1000.0], "fov_angle": [0.1, TAU], "scan_center": [-PI, PI], "scan_half_angle": [0.0, PI], "scan_speed": [0.0, TAU]},
			"robot": {"view_radius": [1.0, 1000.0], "move_speed": [1.0, 400.0]},
		},
		"camera_mount_limits": {"wall": {"half_angle": PI / 2.0}, "ceiling": {"center": 0.0, "half_angle": PI}},
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
		"initial_entities": [
			{"kind": "camera", "cell": [6, 1], "mount_type": "ceiling", "parameters": {"enabled": true, "view_radius": 320.0, "fov_angle": 1.2, "scan_center": 0.0, "scan_half_angle": 0.8, "scan_speed": 1.0}},
			{"kind": "robot", "cell": [4, 3], "parameters": {"view_radius": 320.0, "move_speed": 60.0}, "patrol_path": [[4, 3], [5, 3], [6, 3]]},
			{"kind": "pressure_plate", "cell": [3, 3], "parameters": {}},
			{"kind": "goal", "cell": [9, 5], "parameters": {}},
			{"kind": "contact", "cell": [1, 5], "parameters": {}},
			{"kind": "exit", "cell": [10, 5], "parameters": {}},
		],
	}
