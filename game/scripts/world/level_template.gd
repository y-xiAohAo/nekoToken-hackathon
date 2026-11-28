extends RefCounted
class_name LevelTemplate
## Immutable input definition. No filesystem or resource loading.

var _data: Dictionary = {}


static func from_data(data: Dictionary) -> LevelTemplate:
	var result := LevelTemplate.new()
	if DeviceRegistry.plain(data):
		result._data = data.duplicate(true)
	return result


func validate() -> Array[Dictionary]:
	return [] if instantiate_world() != null else [{"code": "INVALID_TEMPLATE"}]


func instantiate_world() -> WorldState:
	if not DeviceRegistry.fields(_data, ["template_key", "grid_size", "cell_size", "origin", "terrain", "player_spawn", "initial_entities", "device_rules", "obstacle_templates", "initial_obstacles"]):
		return null
	if not DeviceRegistry.rules_valid(_data.device_rules) or not _data.initial_entities is Array or not _data.obstacle_templates is Array or not _data.initial_obstacles is Array or not DeviceRegistry.vector_point(_data.origin) or not DeviceRegistry.number(_data.cell_size):
		return null
	var snapshot: Dictionary = _data.duplicate(true)
	snapshot.erase("initial_entities")
	snapshot.erase("player_spawn")
	snapshot.erase("initial_obstacles")
	snapshot["schema_version"] = 2
	snapshot["player_position"] = _data.player_spawn
	snapshot["player_velocity"] = [0.0, 0.0]
	snapshot["world_revision"] = 0
	snapshot["next_entity_id"] = 1
	snapshot["next_obstacle_id"] = 1
	snapshot["entities"] = []
	snapshot["obstacle_instances"] = []
	for definition: Variant in _data.initial_entities:
		if not DeviceRegistry.definition_valid(definition, _data.device_rules):
			return null
		if definition.kind == "robot" and definition.patrol_path[0] != definition.cell:
			return null
		var position: Vector2 = DeviceRegistry.vector(_data.origin) + (DeviceRegistry.vector(definition.cell) + Vector2(0.5, 0.5)) * float(_data.cell_size)
		snapshot.entities.append(DeviceRegistry.make_entity(definition, snapshot.next_entity_id, position))
		snapshot.next_entity_id += 1
	for raw: Variant in _data.initial_obstacles:
		if not DeviceRegistry.fields(raw, ["template_id", "anchor_cell"]):
			return null
		var data: Dictionary = raw.duplicate(true)
		data["obstacle_id"] = snapshot.next_obstacle_id
		var instance: ObstacleInstance = ObstacleInstance.from_data(data)
		if instance == null:
			return null
		snapshot.obstacle_instances.append(instance.to_data())
		snapshot.next_obstacle_id += 1
	return WorldState.from_snapshot(snapshot)
