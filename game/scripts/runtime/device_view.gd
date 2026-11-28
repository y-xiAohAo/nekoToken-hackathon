extends Node2D
class_name DeviceView


var entity_id: int = 0
var kind: String = ""
var _world: WorldState

@onready var body: Polygon2D = $Body
@onready var solid: StaticBody2D = $Solid
@onready var solid_shape: CollisionShape2D = $Solid/CollisionShape2D


func configure(entity: Dictionary, world: WorldState) -> void:
	# prepare() configures nodes before they enter the tree, so @onready has not run.
	body = $Body
	solid = $Solid
	solid_shape = $Solid/CollisionShape2D
	_world = world
	entity_id = entity.id
	apply(entity)


func apply(entity: Dictionary) -> void:
	kind = entity.kind
	entity_id = entity.id
	if entity.kind != "robot":
		position = _world.origin + (DeviceRegistry.vector(entity.cell) + Vector2(0.5, 0.5)) * _world.cell_size
	var colors: Dictionary = {
		"camera": Color(0.9, 0.85, 0.25, 1),
		"pressure_plate": Color(0.25, 0.75, 0.55, 0.65),
		"goal": Color(0.65, 0.35, 0.9, 1),
		"contact": Color(0.25, 0.65, 0.95, 1),
		"exit": Color(0.9, 0.35, 0.35, 1),
	}
	body.color = colors.get(kind, Color.WHITE)
	var visual_size: float = _world.cell_size * (0.8 if kind == "pressure_plate" else 0.5)
	var half: float = visual_size * 0.5
	body.polygon = PackedVector2Array([Vector2(-half, -half), Vector2(half, -half), Vector2(half, half), Vector2(-half, half)])
	var fixed: bool = kind in DeviceRegistry.FIXED
	solid.set_meta("entity_id", entity_id)
	solid.collision_layer = 1 if fixed else 0
	solid.collision_mask = 6 if fixed else 0
	var rectangle: RectangleShape2D = solid_shape.shape
	rectangle.size = Vector2.ONE * _world.cell_size
	rotation = float(entity.runtime_state.get("heading", 0.0)) if kind == "camera" else 0.0
