extends Node2D
class_name ObstacleView
## Fixed local art and collision. Moving an instance only translates this scene.

var obstacle_id: int = 0


func configure(instance: Dictionary, template: Dictionary, world: WorldState) -> bool:
	if world == null or not DeviceRegistry.fields(instance, ["obstacle_id", "template_id", "anchor_cell"]):
		return false
	if template.get("template_id") != instance.template_id or template.get("footprint") != [[0, 0], [1, 0], [0, 1], [1, 1]]:
		return false
	if not get_node_or_null("Sprite2D") is Sprite2D or not get_node_or_null("StaticBody2D/CollisionShape2D") is CollisionShape2D:
		return false
	obstacle_id = instance.obstacle_id
	name = "Obstacle%d" % obstacle_id
	position = world.origin + Vector2(DeviceRegistry.grid(instance.anchor_cell)) * world.cell_size
	scale = Vector2.ONE * (world.cell_size / 64.0)
	(get_node("StaticBody2D") as StaticBody2D).collision_layer = 1 if template.blocks_movement else 0
	return true
