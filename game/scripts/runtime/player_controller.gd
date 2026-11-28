extends CharacterBody2D
class_name PlayerController


var _touched_entity_ids: Array[int] = []


func advance(input_vector: Vector2, delta: float, rules: Dictionary) -> void:
	var direction: Vector2 = input_vector.limit_length(1.0)
	var target: Vector2 = direction * float(rules.max_speed)
	var rate: float = float(rules.acceleration) if not direction.is_zero_approx() else float(rules.deceleration)
	velocity = velocity.move_toward(target, rate * delta)
	move_and_slide()
	_touched_entity_ids.clear()
	for index: int in get_slide_collision_count():
		var collider: Object = get_slide_collision(index).get_collider()
		if collider != null and collider.has_meta("entity_id"):
			_touched_entity_ids.append(int(collider.get_meta("entity_id")))


func touched_entity_ids() -> Array[int]:
	return _touched_entity_ids.duplicate()


func motion_state() -> Dictionary:
	return {"position": DeviceRegistry.pair(global_position), "velocity": DeviceRegistry.pair(velocity)}


func restore_motion_state(position: Vector2, velocity: Vector2) -> void:
	global_position = position
	self.velocity = velocity
	_touched_entity_ids.clear()
	reset_physics_interpolation()
