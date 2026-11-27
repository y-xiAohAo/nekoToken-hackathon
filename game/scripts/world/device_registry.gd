extends RefCounted
class_name DeviceRegistry
## Internal entity storage. All public reads are detached plain data.

const KINDS: Array[String] = ["camera", "robot", "pressure_plate", "goal", "contact", "exit"]
const FIXED: Array[String] = ["goal", "contact", "exit"]
const CAMERA_NUMBERS: Array[String] = ["view_radius", "fov_angle", "scan_center", "scan_half_angle", "scan_speed"]
const ROBOT_NUMBERS: Array[String] = ["view_radius", "move_speed"]
const SIDES: Dictionary = {"north": Vector2i.UP, "east": Vector2i.RIGHT, "south": Vector2i.DOWN, "west": Vector2i.LEFT}
const VECTOR2I_MIN: int = -2147483648
const VECTOR2I_MAX: int = 2147483647
var _entities: Dictionary = {}


func get_entity(id: int) -> Dictionary:
	return _entities.get(id, {}).duplicate(true)


func snapshot_copy() -> DeviceRegistry:
	var result := DeviceRegistry.new()
	result._entities = _entities.duplicate(true)
	return result


func to_snapshot() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var ids: Array = _entities.keys()
	ids.sort()
	for id: int in ids:
		result.append(get_entity(id))
	return result


func _put(entity: Dictionary) -> void:
	_entities[entity["id"]] = entity.duplicate(true)


func _remove(id: int) -> void:
	_entities.erase(id)


static func fields(value: Variant, required: Array, optional: Array = []) -> bool:
	if not value is Dictionary:
		return false
	for key: Variant in required:
		if not value.has(key):
			return false
	for key: Variant in value:
		if key not in required and key not in optional:
			return false
	return true


static func number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))


static func point(value: Variant) -> bool:
	return value is Array and value.size() == 2 and number(value[0]) and number(value[1])


static func vector_point(value: Variant) -> bool:
	# Scalar parameter pairs may use float64; only actual Vector2 values narrow.
	return point(value) and vector(value).is_finite()


static func cell(value: Variant) -> bool:
	if not value is Array or value.size() != 2 or typeof(value[0]) != TYPE_INT or typeof(value[1]) != TYPE_INT:
		return false
	# Reject before int64 -> Vector2i conversion can wrap into a valid map cell.
	return value[0] >= VECTOR2I_MIN and value[0] <= VECTOR2I_MAX and value[1] >= VECTOR2I_MIN and value[1] <= VECTOR2I_MAX


static func plain(value: Variant) -> bool:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING:
			return true
		TYPE_FLOAT:
			return is_finite(value)
		TYPE_ARRAY:
			for item: Variant in value:
				if not plain(item):
					return false
			return true
		TYPE_DICTIONARY:
			for key: Variant in value:
				if not key is String or not plain(value[key]):
					return false
			return true
	return false


static func vector(value: Array) -> Vector2:
	return Vector2(value[0], value[1])


static func grid(value: Array) -> Vector2i:
	return Vector2i(value[0], value[1])


static func pair(value: Vector2) -> Array:
	return [value.x, value.y]


static func rules_valid(rules: Variant) -> bool:
	if not plain(rules) or not fields(rules, ["parameter_ranges", "camera_mount_limits", "camera_per_anchor"]):
		return false
	if typeof(rules.camera_per_anchor) != TYPE_INT or rules.camera_per_anchor < 1:
		return false
	if not fields(rules.parameter_ranges, ["camera", "robot"]):
		return false
	for kind: String in ["camera", "robot"]:
		var names: Array = CAMERA_NUMBERS if kind == "camera" else ROBOT_NUMBERS
		if not fields(rules.parameter_ranges[kind], names):
			return false
		for key: String in names:
			var bounds: Variant = rules.parameter_ranges[kind][key]
			if not point(bounds) or bounds[0] > bounds[1]:
				return false
	var mounts: Variant = rules.camera_mount_limits
	if not fields(mounts, ["wall", "ceiling"]):
		return false
	if not fields(mounts.wall, ["half_angle"]) or not fields(mounts.ceiling, ["center", "half_angle"]):
		return false
	if not number(mounts.ceiling.center):
		return false
	for mount: String in ["wall", "ceiling"]:
		if not number(mounts[mount].half_angle) or mounts[mount].half_angle < 0 or mounts[mount].half_angle > PI:
			return false
	return true


static func definition_valid(data: Variant, rules: Dictionary) -> bool:
	if not plain(data) or not data is Dictionary or data.get("kind") not in KINDS:
		return false
	var required: Array = ["kind", "cell", "parameters"]
	if data.kind == "camera":
		required.append("mount_type")
		if data.get("mount_type") == "wall":
			required.append("wall_side")
	elif data.kind == "robot":
		required.append("patrol_path")
	if not fields(data, required) or not cell(data.cell):
		return false
	return configuration_valid(data, rules)


static func configuration_valid(entity: Dictionary, rules: Dictionary) -> bool:
	var kind: String = entity.kind
	var parameters: Variant = entity.get("parameters")
	if kind not in ["camera", "robot"]:
		return fields(parameters, [])
	var names: Array = CAMERA_NUMBERS.duplicate() if kind == "camera" else ROBOT_NUMBERS.duplicate()
	if kind == "camera":
		names.append("enabled")
	if not fields(parameters, names):
		return false
	for key: String in names:
		if key == "enabled":
			if typeof(parameters[key]) != TYPE_BOOL:
				return false
			continue
		if not number(parameters[key]):
			return false
		var bounds: Array = rules.parameter_ranges[kind][key]
		if parameters[key] < bounds[0] or parameters[key] > bounds[1]:
			return false
	if parameters.view_radius <= 0:
		return false
	if kind == "robot":
		if parameters.move_speed <= 0 or not entity.get("patrol_path") is Array or entity.patrol_path.is_empty():
			return false
		for waypoint: Variant in entity.patrol_path:
			if not cell(waypoint):
				return false
		return true
	if entity.get("mount_type") not in ["wall", "ceiling"]:
		return false
	if entity.mount_type == "wall" and entity.get("wall_side") not in SIDES:
		return false
	if parameters.fov_angle <= 0 or parameters.fov_angle > TAU or parameters.scan_speed < 0 or parameters.scan_half_angle < 0 or parameters.scan_half_angle > PI:
		return false
	var mount: Dictionary = rules.camera_mount_limits[entity.mount_type]
	var center: float = mount.get("center", 0.0)
	if entity.mount_type == "wall":
		center = Vector2(-SIDES[entity.wall_side]).angle()
	var separation: float = absf(wrapf(parameters.scan_center - center, -PI, PI))
	return mount.half_angle == PI or separation + parameters.scan_half_angle <= mount.half_angle + 0.000001


static func make_entity(data: Dictionary, id: int, position: Vector2) -> Dictionary:
	var entity: Dictionary = data.duplicate(true)
	entity["id"] = id
	match entity.kind:
		"camera":
			entity["runtime_state"] = {"heading": entity.parameters.scan_center, "scan_direction": 1}
		"robot":
			entity.erase("cell")
			entity["runtime_state"] = {"position": pair(position), "path_index": 0, "progress": 0.0, "travel_direction": 1, "transition": {}}
		"pressure_plate":
			entity["runtime_state"] = {"occupants": [], "baseline_ready": false}
		"goal":
			entity["runtime_state"] = {"progress": 0.0, "complete": false}
		"contact":
			entity["runtime_state"] = {"used": false}
		"exit":
			entity["runtime_state"] = {}
	return entity


static func entity_valid(entity: Variant, rules: Dictionary) -> bool:
	if not plain(entity) or not entity is Dictionary or entity.get("kind") not in KINDS:
		return false
	if typeof(entity.get("id")) != TYPE_INT or entity.id < 1:
		return false
	var required: Array = ["id", "kind", "parameters", "runtime_state"]
	if entity.kind == "robot":
		required.append("patrol_path")
	else:
		required.append("cell")
		if not cell(entity.get("cell")):
			return false
	if entity.kind == "camera":
		required.append("mount_type")
		if entity.get("mount_type") == "wall":
			required.append("wall_side")
	if not fields(entity, required) or not configuration_valid(entity, rules):
		return false
	var state: Variant = entity.runtime_state
	match entity.kind:
		"camera":
			if not fields(state, ["heading", "scan_direction"]) or not number(state.heading) or typeof(state.scan_direction) != TYPE_INT or state.scan_direction not in [-1, 1]:
				return false
			return absf(wrapf(state.heading - entity.parameters.scan_center, -PI, PI)) <= entity.parameters.scan_half_angle + 0.000001
		"robot":
			if not fields(state, ["position", "path_index", "progress", "travel_direction", "transition"]):
				return false
			if not vector_point(state.position) or typeof(state.path_index) != TYPE_INT or typeof(state.travel_direction) != TYPE_INT or state.travel_direction not in [-1, 1]:
				return false
			if not number(state.progress) or state.progress < 0 or state.progress >= 1 or not state.transition is Dictionary:
				return false
			if not state.transition.is_empty():
				if not fields(state.transition, ["from_cell", "to_cell", "progress"]) or not cell(state.transition.from_cell) or not cell(state.transition.to_cell):
					return false
				return number(state.transition.progress) and state.transition.progress > 0 and state.transition.progress < 1
			return true
		"pressure_plate":
			if not fields(state, ["occupants", "baseline_ready"]) or not state.occupants is Array or typeof(state.baseline_ready) != TYPE_BOOL:
				return false
			var seen: Dictionary = {}
			for actor: Variant in state.occupants:
				if typeof(actor) != TYPE_INT or actor < 0 or seen.has(actor):
					return false
				seen[actor] = true
			return state.baseline_ready or state.occupants.is_empty()
		"goal":
			return fields(state, ["progress", "complete"]) and number(state.progress) and state.progress >= 0 and typeof(state.complete) == TYPE_BOOL
		"contact":
			return fields(state, ["used"]) and typeof(state.used) == TYPE_BOOL
		"exit":
			return fields(state, [])
	return false
