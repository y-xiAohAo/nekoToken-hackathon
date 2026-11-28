extends RefCounted
class_name DeviceMotion


static func advance_camera(entity: Dictionary, delta: float) -> Dictionary:
	var state: Dictionary = entity.runtime_state.duplicate(true)
	var parameters: Dictionary = entity.parameters
	var half_angle: float = parameters.scan_half_angle
	var speed: float = parameters.scan_speed
	if half_angle <= 0.0 or speed <= 0.0 or delta <= 0.0:
		return state
	var center: float = parameters.scan_center
	var lower: float = center - half_angle
	var upper: float = center + half_angle
	var heading: float = state.heading
	var direction: int = state.scan_direction
	var remaining: float = speed * delta
	for _iteration: int in 1000:
		if remaining <= 0.0000001:
			break
		var next: float = heading + direction * remaining
		if next > upper:
			remaining = next - upper
			heading = upper
			direction = -1
		elif next < lower:
			remaining = lower - next
			heading = lower
			direction = 1
		else:
			heading = next
			remaining = 0.0
	state.heading = heading
	state.scan_direction = direction
	return state


static func patrol_target(entity: Dictionary, delta: float, world: WorldState) -> Dictionary:
	var state: Dictionary = entity.runtime_state.duplicate(true)
	var path: Array = entity.patrol_path
	var remaining: float = float(entity.parameters.move_speed) * delta
	if path.is_empty() or remaining <= 0.0:
		return state
	for _iteration: int in 1000:
		if remaining <= 0.0000001:
			break
		if not state.transition.is_empty():
			var transition: Dictionary = state.transition
			var from_cell: Vector2i = DeviceRegistry.grid(transition.from_cell)
			var to_cell: Vector2i = DeviceRegistry.grid(transition.to_cell)
			var available: float = (1.0 - float(transition.progress)) * world.cell_size
			var used: float = minf(remaining, available)
			transition.progress = float(transition.progress) + used / world.cell_size
			remaining -= used
			state.position = DeviceRegistry.pair(world.cell_to_world(from_cell).lerp(world.cell_to_world(to_cell), float(transition.progress)))
			if float(transition.progress) >= 1.0 - 0.0000001:
				state.position = DeviceRegistry.pair(world.cell_to_world(to_cell))
				state.transition = {}
				state.path_index = 0
				state.progress = 0.0
				state.travel_direction = 1
			continue
		if path.size() == 1:
			state.position = DeviceRegistry.pair(world.cell_to_world(DeviceRegistry.grid(path[0])))
			state.progress = 0.0
			remaining = 0.0
			continue
		var index: int = state.path_index
		var direction: int = state.travel_direction
		var next_index: int = index + direction
		if next_index < 0 or next_index >= path.size():
			return entity.runtime_state.duplicate(true)
		var from_cell: Vector2i = DeviceRegistry.grid(path[index])
		var to_cell: Vector2i = DeviceRegistry.grid(path[next_index])
		var available: float = (1.0 - float(state.progress)) * world.cell_size
		var used: float = minf(remaining, available)
		state.progress = float(state.progress) + used / world.cell_size
		remaining -= used
		state.position = DeviceRegistry.pair(world.cell_to_world(from_cell).lerp(world.cell_to_world(to_cell), float(state.progress)))
		if float(state.progress) >= 1.0 - 0.0000001:
			state.position = DeviceRegistry.pair(world.cell_to_world(to_cell))
			state.path_index = next_index
			state.progress = 0.0
			if next_index == path.size() - 1 and direction == 1:
				state.travel_direction = -1
			elif next_index == 0 and direction == -1:
				state.travel_direction = 1
	return state
