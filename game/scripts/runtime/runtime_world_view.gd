extends Node2D
class_name RuntimeWorldView

const PLAYER_SCENE: PackedScene = preload("res://scenes/runtime/player.tscn")
const ROBOT_SCENE: PackedScene = preload("res://scenes/runtime/robot.tscn")
const DEVICE_SCENE: PackedScene = preload("res://scenes/runtime/device_view.tscn")
const GRAYBOX_TILESET: TileSet = preload("res://scenes/runtime/graybox_tileset.tres")

var _world: WorldState
var _terrain: TileMapLayer
var _player: PlayerController
var _entities: Dictionary = {}
var last_interaction: Dictionary = {}


func build_from_world(world: WorldState) -> bool:
	if world == null:
		return false
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	_world = world.snapshot_copy()
	_entities.clear()
	_terrain = make_terrain_layer(world.to_snapshot())
	if _terrain == null:
		return false
	add_child(_terrain)
	_player = PLAYER_SCENE.instantiate()
	add_child(_player)
	_player.global_position = world.player_position
	for entity: Dictionary in world.registry.to_snapshot():
		var node: Node2D = make_entity_node(entity)
		if node == null:
			return false
		add_child(node)
		_entities[entity.id] = node
	return true


func get_player() -> PlayerController:
	return _player


func get_entity_node(entity_id: int) -> Node2D:
	return _entities.get(entity_id)


func make_terrain_layer(world_data: Dictionary) -> TileMapLayer:
	if not world_data.has_all(["grid_size", "terrain", "cell_size", "origin"]):
		return null
	var layer := TileMapLayer.new()
	layer.tile_set = GRAYBOX_TILESET
	layer.z_index = -10
	layer.position = DeviceRegistry.vector(world_data.origin)
	layer.scale = Vector2.ONE * (float(world_data.cell_size) / 64.0)
	var size: Vector2i = DeviceRegistry.grid(world_data.grid_size)
	for y: int in size.y:
		for x: int in size.x:
			var atlas := Vector2i(1 if world_data.terrain[y][x] == "WALL" else 0, 0)
			layer.set_cell(Vector2i(x, y), 0, atlas)
	return layer


func make_entity_node(entity: Dictionary) -> Node2D:
	if _world == null:
		return null
	if entity.kind == "robot":
		var robot: RobotController = ROBOT_SCENE.instantiate()
		robot.configure(entity.id)
		robot.position = DeviceRegistry.vector(entity.runtime_state.position)
		return robot
	var view: DeviceView = DEVICE_SCENE.instantiate()
	view.configure(entity, _world)
	return view


func replace_terrain(layer: TileMapLayer) -> void:
	if is_instance_valid(_terrain):
		remove_child(_terrain)
		_terrain.queue_free()
	_terrain = layer
	add_child(_terrain)
	move_child(_terrain, 0)


func replace_entity(entity_id: int, node: Node2D) -> void:
	if _entities.has(entity_id):
		var old: Node = _entities[entity_id]
		remove_child(old)
		old.queue_free()
	_entities[entity_id] = node
	add_child(node)


func remove_entity(entity_id: int) -> void:
	if not _entities.has(entity_id):
		return
	var old: Node = _entities[entity_id]
	_entities.erase(entity_id)
	remove_child(old)
	old.queue_free()


func step_motion(
	candidate: WorldState,
	input_vector: Vector2,
	delta: float,
	rules: Dictionary,
	expected_tick: int = 0,
	interact_pressed: bool = false,
	cancel_pressed: bool = false
) -> Array[Dictionary]:
	var errors: Array[Dictionary] = []
	if _player == null:
		return [{"code": "MISSING_PLAYER"}]
	_player.advance(input_vector, delta, rules)
	for entity: Dictionary in candidate.registry.to_snapshot():
		if entity.kind == "robot":
			var robot: RobotController = _entities.get(entity.id)
			if robot == null:
				errors.append({"code": "MISSING_ENTITY", "id": entity.id})
				continue
			var next: Dictionary = robot.advance(entity, candidate, _player, delta)
			if next.is_empty():
				errors.append({"code": "INVALID_ROBOT_STEP", "id": entity.id})
				continue
			entity.runtime_state = next
			candidate.registry._put(entity)
		elif entity.kind == "camera":
			entity.runtime_state = DeviceMotion.advance_camera(entity, delta)
			candidate.registry._put(entity)
			var view: DeviceView = _entities.get(entity.id)
			if view != null:
				view.apply(entity)
	candidate.player_position = _player.global_position
	candidate.player_velocity = _player.velocity
	last_interaction = InteractionSystem.advance(candidate, _player, input_vector, interact_pressed, cancel_pressed, expected_tick, delta, rules)
	errors.append_array(last_interaction.errors)
	return errors
