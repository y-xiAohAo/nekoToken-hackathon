extends RefCounted
class_name InteractionSystem


static func advance(
	candidate: WorldState,
	player: PlayerController,
	input_vector: Vector2,
	interact_pressed: bool,
	cancel_pressed: bool,
	expected_tick: int,
	delta: float,
	rules: Dictionary
) -> Dictionary:
	var result: Dictionary = {"events": [], "goal_complete": false, "at_exit": false, "contact_requested": false, "contact_id": 0, "errors": []}
	var distance_limit: float = float(rules.get("interaction_distance", 56.0))
	var duration: float = float(rules.get("goal_duration", 2.0))
	if distance_limit <= 0 or duration <= 0:
		result.errors.append({"code": "INVALID_INTERACTION_RULES"})
		return result
	var entities: Array[Dictionary] = candidate.registry.to_snapshot()
	var goals: Array[Dictionary] = []
	var active_goal: Dictionary = {}
	for entity: Dictionary in entities:
		if entity.kind == "goal":
			goals.append(entity)
			if entity.runtime_state.active:
				if not active_goal.is_empty():
					result.errors.append({"code": "MULTIPLE_ACTIVE_GOALS"})
					return result
				active_goal = entity
	var handled_goal: bool = not active_goal.is_empty()
	if active_goal.is_empty() and interact_pressed and not cancel_pressed and input_vector.is_zero_approx():
		var nearest: Dictionary = {}
		var nearest_distance: float = distance_limit
		for goal: Dictionary in goals:
			if goal.runtime_state.complete:
				continue
			var distance: float = candidate.player_position.distance_to(candidate.cell_to_world(DeviceRegistry.grid(goal.cell)))
			if distance <= nearest_distance:
				nearest = goal
				nearest_distance = distance
		if not nearest.is_empty():
			active_goal = nearest
			active_goal.runtime_state.active = true
			active_goal.runtime_state.progress = 0.0
			candidate.registry._put(active_goal)
			result.events.append({"goal_id": active_goal.id, "tick": expected_tick, "type": "GOAL_OPERATION_STARTED", "progress": 0.0})
			handled_goal = true
	if not active_goal.is_empty():
		var position: Vector2 = candidate.cell_to_world(DeviceRegistry.grid(active_goal.cell))
		var interrupted: bool = cancel_pressed or not input_vector.is_zero_approx() or candidate.player_position.distance_to(position) > distance_limit
		if interrupted and not active_goal.runtime_state.complete:
			result.events.append({"goal_id": active_goal.id, "tick": expected_tick, "type": "GOAL_OPERATION_CANCELLED", "progress": active_goal.runtime_state.progress})
			active_goal.runtime_state.active = false
			active_goal.runtime_state.progress = 0.0
		elif not active_goal.runtime_state.complete:
			active_goal.runtime_state.progress = minf(1.0, float(active_goal.runtime_state.progress) + delta / duration)
			if active_goal.runtime_state.progress >= 1.0 - 0.000001:
				active_goal.runtime_state.progress = 1.0
				active_goal.runtime_state.active = false
				active_goal.runtime_state.complete = true
				result.events.append({"goal_id": active_goal.id, "tick": expected_tick, "type": "GOAL_OPERATION_COMPLETED", "progress": 1.0})
		candidate.registry._put(active_goal)
	if not handled_goal and interact_pressed and input_vector.is_zero_approx():
		var nearest_contact: Dictionary = {}
		var nearest_distance: float = distance_limit
		for entity: Dictionary in entities:
			if entity.kind != "contact" or entity.runtime_state.used:
				continue
			var distance: float = candidate.player_position.distance_to(candidate.cell_to_world(DeviceRegistry.grid(entity.cell)))
			if distance <= nearest_distance:
				nearest_contact = entity
				nearest_distance = distance
		if not nearest_contact.is_empty():
			result.contact_requested = true
			result.contact_id = nearest_contact.id
	var touched: Array[int] = player.touched_entity_ids()
	for entity: Dictionary in entities:
		if entity.kind == "exit" and entity.id in touched:
			result.at_exit = true
			break
	var all_complete: bool = not goals.is_empty()
	for goal: Dictionary in goals:
		var current: Dictionary = active_goal if not active_goal.is_empty() and active_goal.id == goal.id else goal
		all_complete = all_complete and current.runtime_state.complete
	result.goal_complete = all_complete
	return result
