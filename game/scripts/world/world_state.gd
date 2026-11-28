extends RefCounted
class_name WorldState
## A detached world value; only the command service owns the active instance.

var template_key: String = ""
var grid_size: Vector2i
var cell_size: float = 1.0
var origin: Vector2
var terrain: Array = []
var registry: DeviceRegistry = DeviceRegistry.new()
var player_position: Vector2
var player_velocity: Vector2
var world_revision: int = 0
var next_entity_id: int = 1
var device_rules: Dictionary = {}


func cell_to_world(cell: Vector2i) -> Vector2:
	return origin + (Vector2(cell) + Vector2(0.5, 0.5)) * cell_size


func world_to_cell(position: Vector2) -> Vector2i:
	return Vector2i(((position - origin) / cell_size).floor())


func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < grid_size.x and cell.y < grid_size.y


func get_cell_profile(cell: Vector2i) -> Dictionary:
	var kind: String = terrain[cell.y][cell.x] if in_bounds(cell) else "OUTSIDE"
	var solid: bool = kind != "FLOOR"
	var plate_id: int = 0
	var exit_id: int = 0
	for entity: Dictionary in registry.to_snapshot():
		if not entity.has("cell") or DeviceRegistry.grid(entity.cell) != cell:
			continue
		if entity.kind in DeviceRegistry.FIXED:
			solid = true
		if entity.kind == "pressure_plate":
			plate_id = entity.id
		if entity.kind == "exit":
			exit_id = entity.id
	return {"terrain": kind, "blocks_movement": solid, "blocks_vision": solid, "plate_id": plate_id, "exit_id": exit_id}


func snapshot_copy() -> WorldState:
	return from_snapshot(to_snapshot())


func to_snapshot() -> Dictionary:
	return {
		"schema_version": 1, "template_key": template_key, "grid_size": [grid_size.x, grid_size.y],
		"cell_size": cell_size, "origin": DeviceRegistry.pair(origin), "terrain": terrain.duplicate(true),
		"entities": registry.to_snapshot(), "player_position": DeviceRegistry.pair(player_position),
		"player_velocity": DeviceRegistry.pair(player_velocity), "world_revision": world_revision,
		"next_entity_id": next_entity_id, "device_rules": device_rules.duplicate(true),
	}


static func from_snapshot(data: Dictionary) -> WorldState:
	if not DeviceRegistry.plain(data) or not DeviceRegistry.fields(data, ["schema_version", "template_key", "grid_size", "cell_size", "origin", "terrain", "entities", "player_position", "player_velocity", "world_revision", "next_entity_id", "device_rules"]):
		return null
	if typeof(data.schema_version) != TYPE_INT or data.schema_version != 1 or not data.template_key is String or data.template_key.is_empty():
		return null
	if not DeviceRegistry.cell(data.grid_size) or data.grid_size[0] <= 0 or data.grid_size[1] <= 0:
		return null
	if not DeviceRegistry.number(data.cell_size) or data.cell_size <= 0 or not DeviceRegistry.vector_point(data.origin):
		return null
	if not DeviceRegistry.vector_point(data.player_position) or not DeviceRegistry.vector_point(data.player_velocity):
		return null
	if typeof(data.world_revision) != TYPE_INT or data.world_revision < 0 or typeof(data.next_entity_id) != TYPE_INT or data.next_entity_id < 1:
		return null
	if not terrain_valid(data.terrain, DeviceRegistry.grid(data.grid_size)) or not DeviceRegistry.rules_valid(data.device_rules) or not data.entities is Array:
		return null
	var world := WorldState.new()
	world.template_key = data.template_key
	world.grid_size = DeviceRegistry.grid(data.grid_size)
	world.cell_size = data.cell_size
	world.origin = DeviceRegistry.vector(data.origin)
	world.terrain = data.terrain.duplicate(true)
	world.player_position = DeviceRegistry.vector(data.player_position)
	world.player_velocity = DeviceRegistry.vector(data.player_velocity)
	world.world_revision = data.world_revision
	world.next_entity_id = data.next_entity_id
	world.device_rules = data.device_rules.duplicate(true)
	for entity: Variant in data.entities:
		if not DeviceRegistry.entity_valid(entity, world.device_rules) or not world.registry.get_entity(entity.id).is_empty() or entity.id >= world.next_entity_id:
			return null
		world.registry._put(entity)
	return world if world.validate().is_empty() else null


static func terrain_valid(value: Variant, size: Vector2i) -> bool:
	if not value is Array or value.size() != size.y:
		return false
	for row: Variant in value:
		if not row is Array or row.size() != size.x:
			return false
		for tile: Variant in row:
			if tile not in ["FLOOR", "WALL"]:
				return false
	return true


func validate() -> Array[Dictionary]:
	if not terrain_valid(terrain, grid_size) or not DeviceRegistry.rules_valid(device_rules):
		return [{"code": "INVALID_WORLD"}]
	if not origin.is_finite() or not player_position.is_finite() or not player_velocity.is_finite() or not is_finite(cell_size) or cell_size <= 0:
		return [{"code": "INVALID_WORLD"}]
	# Positive uniform scale: the first/last centers bound the grid's coordinates.
	if not cell_to_world(Vector2i.ZERO).is_finite() or not cell_to_world(grid_size - Vector2i.ONE).is_finite():
		return [{"code": "INVALID_WORLD"}]
	var solids: Dictionary = {}
	var plates: Dictionary = {}
	var mounts: Dictionary = {}
	var entities: Array[Dictionary] = registry.to_snapshot()
	for entity: Dictionary in entities:
		if not DeviceRegistry.entity_valid(entity, device_rules):
			return [{"code": "INVALID_PARAMETER"}]
		if entity.kind in ["camera", "robot"]:
			var cell_count: float = float(entity.parameters.view_radius) / cell_size
			if not is_finite(cell_count) or roundf(cell_count) < 1.0 or absf(cell_count - roundf(cell_count)) > 0.000001:
				return [{"code": "INVALID_PARAMETER"}]
		if entity.kind == "robot":
			continue
		var cell: Vector2i = DeviceRegistry.grid(entity.cell)
		if not in_bounds(cell) or terrain[cell.y][cell.x] != "FLOOR":
			return [{"code": "INVALID_POSITION"}]
		if entity.kind in DeviceRegistry.FIXED:
			if solids.has(cell):
				return [{"code": "OCCUPANCY_CONFLICT"}]
			solids[cell] = true
		elif entity.kind == "pressure_plate":
			if plates.has(cell):
				return [{"code": "OCCUPANCY_CONFLICT"}]
			plates[cell] = true
		elif entity.kind == "camera":
			var key: String = str(entity.cell) + entity.mount_type + entity.get("wall_side", "")
			mounts[key] = mounts.get(key, 0) + 1
			if mounts[key] > device_rules.camera_per_anchor:
				return [{"code": "OCCUPANCY_CONFLICT"}]
			if entity.mount_type == "wall":
				var support: Vector2i = cell + DeviceRegistry.SIDES[entity.wall_side]
				if not in_bounds(support) or terrain[support.y][support.x] != "WALL":
					return [{"code": "INVALID_POSITION"}]
	for cell: Vector2i in plates:
		if solids.has(cell):
			return [{"code": "OCCUPANCY_CONFLICT"}]
	if get_cell_profile(world_to_cell(player_position)).blocks_movement:
		return [{"code": "INVALID_POSITION"}]
	var active_goals: int = 0
	for entity: Dictionary in entities:
		if entity.kind == "camera" and solids.has(DeviceRegistry.grid(entity.cell)):
			return [{"code": "OCCUPANCY_CONFLICT"}]
		if entity.kind == "robot" and not _robot_valid(entity):
			return [{"code": "INVALID_PATH"}]
		if entity.kind == "goal" and entity.runtime_state.active:
			active_goals += 1
		if entity.kind == "pressure_plate":
			for actor: int in entity.runtime_state.occupants:
				if actor != 0 and registry.get_entity(actor).get("kind") != "robot":
					return [{"code": "INVALID_WORLD"}]
	if active_goals > 1:
		return [{"code": "INVALID_WORLD"}]
	return []


func _robot_valid(entity: Dictionary) -> bool:
	var path: Array = entity.patrol_path
	for i: int in path.size():
		var cell: Vector2i = DeviceRegistry.grid(path[i])
		if get_cell_profile(cell).blocks_movement:
			return false
		if i > 0 and not adjacent(DeviceRegistry.grid(path[i - 1]), cell):
			return false
	var state: Dictionary = entity.runtime_state
	if state.path_index < 0 or state.path_index >= path.size():
		return false
	var position: Vector2 = DeviceRegistry.vector(state.position)
	var expected: Vector2 = cell_to_world(DeviceRegistry.grid(path[state.path_index]))
	if not state.transition.is_empty():
		var transition: Dictionary = state.transition
		var start: Vector2i = DeviceRegistry.grid(transition.from_cell)
		var end: Vector2i = DeviceRegistry.grid(transition.to_cell)
		if state.path_index != 0 or state.progress != 0 or transition.to_cell != path[0] or not adjacent(start, end):
			return false
		if get_cell_profile(start).blocks_movement or get_cell_profile(end).blocks_movement:
			return false
		expected = cell_to_world(start).lerp(cell_to_world(end), transition.progress)
	elif path.size() == 1:
		if state.progress != 0:
			return false
	else:
		var next: int = state.path_index + state.travel_direction
		if next < 0 or next >= path.size():
			return false
		expected = expected.lerp(cell_to_world(DeviceRegistry.grid(path[next])), state.progress)
	return position.is_equal_approx(expected)


static func adjacent(a: Vector2i, b: Vector2i) -> bool:
	var delta: Vector2i = (a - b).abs()
	return delta.x + delta.y == 1


func _set_patrol(entity: Dictionary, path: Array) -> bool:
	if path.is_empty():
		return false
	for waypoint: Variant in path:
		if not DeviceRegistry.cell(waypoint):
			return false
	var state: Dictionary = entity.runtime_state
	var transition: Dictionary = state.transition.duplicate(true)
	var anchor: Array = entity.patrol_path[state.path_index]
	if not transition.is_empty():
		anchor = transition.to_cell
	elif state.progress > 0:
		anchor = entity.patrol_path[state.path_index + state.travel_direction]
		transition = {"from_cell": entity.patrol_path[state.path_index].duplicate(), "to_cell": anchor.duplicate(), "progress": state.progress}
	if path[0] != anchor:
		return false
	if entity.patrol_path == path:
		return true
	entity["patrol_path"] = path.duplicate(true)
	state["path_index"] = 0
	state["progress"] = 0.0
	state["travel_direction"] = 1
	state["transition"] = transition
	return true
