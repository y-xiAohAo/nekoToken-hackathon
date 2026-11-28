extends RefCounted
class_name VisionGeometry
## Deterministic continuous region / discrete reliable-cell conversion.

const ANGLE_TOLERANCE: float = 0.000001
const LINEAR_RATIO_TOLERANCE: float = 0.000001

static func observer_position(world: WorldState, entity: Dictionary) -> Vector2:
	if world == null:
		return Vector2(INF, INF)
	if entity.get("kind") == "camera" and DeviceRegistry.cell(entity.get("cell")):
		return world.cell_to_world(DeviceRegistry.grid(entity.cell))
	if entity.get("kind") == "robot" and DeviceRegistry.vector_point(entity.get("runtime_state", {}).get("position")):
		return DeviceRegistry.vector(entity.runtime_state.position)
	return Vector2(INF, INF)

static func reliable_cells(world: WorldState, entity: Dictionary) -> Dictionary:
	var failure: Dictionary = {"ok": false, "cells": [], "errors": [{"code": "INVALID_SENSOR"}]}
	if world == null or world.cell_size <= 0 or not is_finite(world.cell_size) or world.grid_size.x <= 0 or world.grid_size.y <= 0:
		return failure
	var kind: String = entity.get("kind", "")
	if kind not in ["camera", "robot"] or not entity.get("parameters") is Dictionary:
		return failure
	var parameters: Dictionary = entity.parameters
	if not DeviceRegistry.number(parameters.get("view_radius")):
		return {"ok": false, "cells": [], "errors": [{"code": "INVALID_VIEW_RADIUS"}]}
	var radius: float = float(parameters.view_radius)
	var cell_count: float = radius / world.cell_size
	if not is_finite(cell_count) or radius <= 0.0 or roundf(cell_count) < 1.0 or absf(cell_count - roundf(cell_count)) > LINEAR_RATIO_TOLERANCE:
		return {"ok": false, "cells": [], "errors": [{"code": "INVALID_VIEW_RADIUS"}]}
	var origin: Vector2 = observer_position(world, entity)
	if not origin.is_finite():
		return failure
	var fov: float = TAU
	var heading: float = 0.0
	if kind == "camera":
		if not DeviceRegistry.number(parameters.get("fov_angle")) or not DeviceRegistry.number(entity.get("runtime_state", {}).get("heading")):
			return failure
		fov = float(parameters.fov_angle)
		heading = float(entity.runtime_state.heading)
		if fov <= 0.0 or fov > TAU + ANGLE_TOLERANCE:
			return failure
	var cells: Array[Vector2i] = []
	var min_x: int = maxi(0, int(floor((origin.x - radius - world.origin.x) / world.cell_size)))
	var min_y: int = maxi(0, int(floor((origin.y - radius - world.origin.y) / world.cell_size)))
	var max_x: int = mini(world.grid_size.x - 1, int(floor((origin.x + radius - world.origin.x) / world.cell_size)))
	var max_y: int = mini(world.grid_size.y - 1, int(floor((origin.y + radius - world.origin.y) / world.cell_size)))
	for y: int in range(min_y, max_y + 1):
		for x: int in range(min_x, max_x + 1):
			var cell := Vector2i(x, y)
			if world.get_cell_profile(cell).blocks_vision:
				continue
			if _positive_region_overlap(world, origin, radius, heading, fov, cell) and is_cell_reliable(world, origin, cell):
				cells.append(cell)
	return {"ok": true, "cells": cells, "errors": []}

static func _positive_region_overlap(world: WorldState, origin: Vector2, radius: float, heading: float, fov: float, cell: Vector2i) -> bool:
	var left: float = world.origin.x + cell.x * world.cell_size
	var top: float = world.origin.y + cell.y * world.cell_size
	var rect: Array[Vector2] = [Vector2(left, top), Vector2(left + world.cell_size, top), Vector2(left + world.cell_size, top + world.cell_size), Vector2(left, top + world.cell_size)]
	var tolerance: float = world.cell_size * LINEAR_RATIO_TOLERANCE
	if fov >= TAU - ANGLE_TOLERANCE:
		return _polygon_area(rect) > tolerance * tolerance and _distance_to_polygon(origin, rect) < radius - tolerance
	var pieces: int = maxi(1, int(ceil(fov / PI)))
	var piece_width: float = fov / pieces
	for part: int in pieces:
		var start_angle: float = heading - fov * 0.5 + part * piece_width
		var end_angle: float = start_angle + piece_width
		var start_vector := Vector2.from_angle(start_angle)
		var end_vector := Vector2.from_angle(end_angle)
		var clipped: Array[Vector2] = _clip(rect, origin, start_vector, true)
		clipped = _clip(clipped, origin, end_vector, false)
		if _polygon_area(clipped) > tolerance * world.cell_size and _distance_to_polygon(origin, clipped) < radius - tolerance:
			return true
	return false

static func _clip(polygon: Array[Vector2], origin: Vector2, ray: Vector2, keep_left: bool) -> Array[Vector2]:
	var output: Array[Vector2] = []
	if polygon.is_empty():
		return output
	for index: int in polygon.size():
		var a: Vector2 = polygon[index]
		var b: Vector2 = polygon[(index + 1) % polygon.size()]
		var da: float = ray.cross(a - origin) * (1.0 if keep_left else -1.0)
		var db: float = ray.cross(b - origin) * (1.0 if keep_left else -1.0)
		var inside_a: bool = da >= 0.0
		var inside_b: bool = db >= 0.0
		if inside_a:
			output.append(a)
		if inside_a != inside_b and absf(da - db) > 0.0:
			output.append(a.lerp(b, da / (da - db)))
	return output

static func _polygon_area(polygon: Array[Vector2]) -> float:
	if polygon.size() < 3:
		return 0.0
	var twice_area: float = 0.0
	for index: int in polygon.size():
		twice_area += polygon[index].cross(polygon[(index + 1) % polygon.size()])
	return absf(twice_area) * 0.5

static func _distance_to_polygon(point: Vector2, polygon: Array[Vector2]) -> float:
	if polygon.size() < 3:
		return INF
	var inside: bool = true
	var minimum: float = INF
	for index: int in polygon.size():
		var a: Vector2 = polygon[index]
		var b: Vector2 = polygon[(index + 1) % polygon.size()]
		if (b - a).cross(point - a) < -0.00000001:
			inside = false
		var edge: Vector2 = b - a
		if edge.length_squared() > 0.0:
			var fraction: float = clampf((point - a).dot(edge) / edge.length_squared(), 0.0, 1.0)
			minimum = minf(minimum, point.distance_to(a + edge * fraction))
	return 0.0 if inside else minimum

static func is_cell_reliable(world: WorldState, origin: Vector2, target: Vector2i) -> bool:
	if world == null or not origin.is_finite() or not world.in_bounds(target) or world.get_cell_profile(target).blocks_vision:
		return false
	var destination: Vector2 = world.cell_to_world(target)
	var start: Vector2 = (origin - world.origin) / world.cell_size
	var end: Vector2 = (destination - world.origin) / world.cell_size
	var delta: Vector2 = end - start
	var times: Array[float] = [0.0, 1.0]
	if not is_zero_approx(delta.x):
		for line_x: int in range(int(floor(minf(start.x, end.x))) + 1, int(ceil(maxf(start.x, end.x)))):
			var tx: float = (line_x - start.x) / delta.x
			if tx > 0.0 and tx < 1.0:
				times.append(tx)
	if not is_zero_approx(delta.y):
		for line_y: int in range(int(floor(minf(start.y, end.y))) + 1, int(ceil(maxf(start.y, end.y)))):
			var ty: float = (line_y - start.y) / delta.y
			if ty > 0.0 and ty < 1.0:
				times.append(ty)
	times.sort()
	var samples: Array[float] = []
	for index: int in times.size():
		if samples.is_empty() or absf(times[index] - samples[-1]) > 0.000000001:
			samples.append(times[index])
	var source: Vector2i = world.world_to_cell(origin)
	var touched: Dictionary = {}
	for index: int in samples.size():
		_touch_cells(start + delta * samples[index], touched)
		if index + 1 < samples.size():
			_touch_cells(start + delta * ((samples[index] + samples[index + 1]) * 0.5), touched)
	for cell: Vector2i in touched:
		if cell == source or cell == target:
			continue
		if world.in_bounds(cell) and world.get_cell_profile(cell).blocks_vision:
			return false
	return true

static func _touch_cells(point: Vector2, output: Dictionary) -> void:
	var xs: Array[int] = [int(floor(point.x))]
	var ys: Array[int] = [int(floor(point.y))]
	if absf(point.x - roundf(point.x)) <= 0.000000001:
		xs = [int(roundf(point.x)) - 1, int(roundf(point.x))]
	if absf(point.y - roundf(point.y)) <= 0.000000001:
		ys = [int(roundf(point.y)) - 1, int(roundf(point.y))]
	for x: int in xs:
		for y: int in ys:
			output[Vector2i(x, y)] = true
