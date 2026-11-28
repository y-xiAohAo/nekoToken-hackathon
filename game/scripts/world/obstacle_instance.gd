extends RefCounted
class_name ObstacleInstance
## Stable identity; occupied cells are always derived from its template.

var obstacle_id: int = 0
var template_id: String = ""
var anchor_cell: Vector2i


static func from_data(data: Dictionary) -> ObstacleInstance:
	if not DeviceRegistry.plain(data) or not DeviceRegistry.fields(data,
		["obstacle_id", "template_id", "anchor_cell"]):
		return null
	if typeof(data.obstacle_id) != TYPE_INT or data.obstacle_id < 1 or not data.template_id is String or data.template_id.is_empty():
		return null
	if not DeviceRegistry.cell(data.anchor_cell) or data.anchor_cell[0] < 0 or data.anchor_cell[1] < 0:
		return null
	var result := ObstacleInstance.new()
	result.obstacle_id = data.obstacle_id
	result.template_id = data.template_id
	result.anchor_cell = DeviceRegistry.grid(data.anchor_cell)
	return result


func to_data() -> Dictionary:
	return {"obstacle_id": obstacle_id, "template_id": template_id,
		"anchor_cell": [anchor_cell.x, anchor_cell.y]}
