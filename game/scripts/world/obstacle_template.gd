extends RefCounted
class_name ObstacleTemplate
## Fixed local footprint and scene asset for one movable obstacle kind.

var template_id: String = ""
var footprint: Array[Vector2i] = []
var blocks_movement: bool = true
var blocks_vision: bool = true
var scene_path: String = ""


static func from_data(data: Dictionary) -> ObstacleTemplate:
	if not DeviceRegistry.plain(data) or not DeviceRegistry.fields(data,
		["template_id", "footprint", "blocks_movement", "blocks_vision", "scene_path"]):
		return null
	if not data.template_id is String or data.template_id.is_empty() or not data.footprint is Array or data.footprint.is_empty():
		return null
	if typeof(data.blocks_movement) != TYPE_BOOL or typeof(data.blocks_vision) != TYPE_BOOL:
		return null
	if not data.scene_path is String or not data.scene_path.begins_with("res://") or not data.scene_path.ends_with(".tscn"):
		return null
	var cells: Array[Vector2i] = []
	for offset: Variant in data.footprint:
		if not DeviceRegistry.cell(offset) or offset[0] < 0 or offset[1] < 0:
			return null
		var cell := DeviceRegistry.grid(offset)
		if cell in cells:
			return null
		cells.append(cell)
	if Vector2i.ZERO not in cells:
		return null
	var result := ObstacleTemplate.new()
	result.template_id = data.template_id
	result.footprint = cells
	result.blocks_movement = data.blocks_movement
	result.blocks_vision = data.blocks_vision
	result.scene_path = data.scene_path
	return result


func to_data() -> Dictionary:
	var cells: Array = []
	for offset: Vector2i in footprint:
		cells.append([offset.x, offset.y])
	return {"template_id": template_id, "footprint": cells, "blocks_movement": blocks_movement,
		"blocks_vision": blocks_vision, "scene_path": scene_path}


func covered_cells(anchor_cell: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for offset: Vector2i in footprint:
		cells.append(anchor_cell + offset)
	return cells
