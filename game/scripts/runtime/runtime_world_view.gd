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
var _obstacles: Dictionary = {}
var _marked_target_id: int = 0
var _route_preview: Node2D
var _route_preview_cells: Array = []
var last_interaction: Dictionary = {}


func build_from_world(world: WorldState) -> bool:
	if world == null:
		return false
	_route_preview = null
	_route_preview_cells.clear()
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	_world = world.snapshot_copy()
	_entities.clear()
	_obstacles.clear()
	_marked_target_id = 0
	_terrain = make_terrain_layer(world.to_snapshot())
	if _terrain == null:
		return false
	add_child(_terrain)
	_player = PLAYER_SCENE.instantiate()
	add_child(_player)
	_player.global_position = world.player_position
	for instance: Dictionary in world.obstacle_instances:
		var obstacle: Node2D = make_obstacle_node(instance, world)
		if obstacle == null:
			return false
		add_child(obstacle)
		_obstacles[instance.obstacle_id] = obstacle
	for entity: Dictionary in world.registry.to_snapshot():
		var node: Node2D = make_entity_node(entity, world)
		if node == null:
			return false
		add_child(node)
		_entities[entity.id] = node
	return true


func get_player() -> PlayerController:
	return _player


func get_entity_node(entity_id: int) -> Node2D:
	return _entities.get(entity_id)


func is_contact_target_displayed(entity_id: int) -> bool:
	var node: Variant = _entities.get(entity_id)
	var kind: String = str(_world.registry.get_entity(entity_id).get("kind", "")) if _world != null else ""
	if not node is Node2D or not node.is_visible_in_tree() or not is_inside_tree() or kind not in ["camera", "robot"]:
		return false
	if kind == "camera" and not node is DeviceView or kind == "robot" and not node is RobotController:
		return false
	var screen_position: Vector2 = node.get_global_transform_with_canvas() * Vector2.ZERO
	return get_viewport().get_visible_rect().has_point(screen_position)


func is_camera_displayed(entity_id: int) -> bool:
	return _world != null and _world.registry.get_entity(entity_id).get("kind") == "camera" and is_contact_target_displayed(entity_id)


func contact_target_at_screen_position(screen_position: Vector2) -> int:
	return _target_at_screen_position(screen_position, "")


func camera_at_screen_position(screen_position: Vector2) -> int:
	return _target_at_screen_position(screen_position, "camera")


func _target_at_screen_position(screen_position: Vector2, only_kind: String) -> int:
	if not is_inside_tree() or not get_viewport().get_visible_rect().has_point(screen_position):
		return 0
	var closest_id: int = 0
	var closest_distance: float = INF
	for id: Variant in _entities:
		if not is_contact_target_displayed(id) or not only_kind.is_empty() and _world.registry.get_entity(id).kind != only_kind:
			continue
		var node: Node2D = _entities[id]
		var screen_center: Vector2 = node.get_global_transform_with_canvas() * Vector2.ZERO
		var radius: float = _world.cell_size * 0.35
		var distance: float = screen_position.distance_to(screen_center)
		if distance <= radius and distance < closest_distance:
			closest_id = id
			closest_distance = distance
	return closest_id


func mark_contact_target(entity_id: int) -> void:
	if _marked_target_id > 0:
		var previous: Variant = _entities.get(_marked_target_id)
		if previous is DeviceView or previous is RobotController:
			previous.set_marked(false)
	_marked_target_id = entity_id if is_contact_target_displayed(entity_id) else 0
	if _marked_target_id > 0:
		_entities[_marked_target_id].set_marked(true)


func mark_camera(entity_id: int) -> void:
	mark_contact_target(entity_id if entity_id == 0 or is_camera_displayed(entity_id) else 0)


func set_contact_route_preview(cells: Array) -> void:
	_route_preview_cells = cells.duplicate(true)
	if _route_preview == null:
		_route_preview = Node2D.new()
		_route_preview.z_index = 20
		add_child(_route_preview)
	for child: Node in _route_preview.get_children():
		_route_preview.remove_child(child)
		child.queue_free()
	_route_preview.visible = not cells.is_empty()
	if cells.is_empty() or _world == null:
		return
	var points := PackedVector2Array()
	for cell: Variant in cells:
		if not DeviceRegistry.cell(cell):
			_route_preview_cells.clear()
			_route_preview.visible = false
			return
		points.append(_world.cell_to_world(DeviceRegistry.grid(cell)))
	if points.size() > 1:
		var line := Line2D.new()
		line.points = points
		line.width = 4.0
		line.default_color = Color(0.2, 0.9, 0.95, 0.85)
		_route_preview.add_child(line)
	for point: Vector2 in points:
		var marker := Polygon2D.new()
		marker.position = point
		marker.polygon = PackedVector2Array([Vector2(0, -7), Vector2(7, 0), Vector2(0, 7), Vector2(-7, 0)])
		marker.color = Color(0.95, 0.85, 0.2, 0.95)
		_route_preview.add_child(marker)


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


func make_entity_node(entity: Dictionary, candidate: WorldState) -> Node2D:
	if candidate == null:
		return null
	if entity.kind == "robot":
		var robot: RobotController = ROBOT_SCENE.instantiate()
		robot.configure(entity.id)
		robot.position = DeviceRegistry.vector(entity.runtime_state.position)
		return robot
	var view: DeviceView = DEVICE_SCENE.instantiate()
	view.configure(entity, candidate)
	return view


func make_obstacle_node(instance: Dictionary, candidate: WorldState) -> Node2D:
	if candidate == null:
		return null
	var template: ObstacleTemplate = candidate.obstacle_template(instance.get("template_id", ""))
	if template == null or template.scene_path.is_empty():
		return null
	var scene: PackedScene = load(template.scene_path)
	if scene == null:
		return null
	var node: Node = scene.instantiate()
	if not node is ObstacleView or not node.configure(instance, template.to_data(), candidate):
		node.free()
		return null
	return node


func replace_obstacle(obstacle_id: int, node: Node2D) -> void:
	if _obstacles.has(obstacle_id):
		var old: Node = _obstacles[obstacle_id]
		remove_child(old)
		old.queue_free()
	_obstacles[obstacle_id] = node
	add_child(node)


func remove_obstacle(obstacle_id: int) -> void:
	if not _obstacles.has(obstacle_id):
		return
	var old: Node = _obstacles[obstacle_id]
	_obstacles.erase(obstacle_id)
	remove_child(old)
	old.queue_free()


func accept_committed_world(world: WorldState) -> void:
	_world = world.snapshot_copy() if world != null else null


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
	if entity_id == _marked_target_id and (node is DeviceView or node is RobotController):
		node.set_marked(true)


func remove_entity(entity_id: int) -> void:
	if not _entities.has(entity_id):
		return
	if entity_id == _marked_target_id:
		_marked_target_id = 0
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
