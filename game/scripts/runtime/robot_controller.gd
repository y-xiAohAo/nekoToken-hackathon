extends AnimatableBody2D
class_name RobotController


var entity_id: int = 0


func configure(p_entity_id: int) -> void:
	entity_id = p_entity_id


func advance(entity: Dictionary, world: WorldState, player: PlayerController, delta: float) -> Dictionary:
	var previous: Dictionary = entity.runtime_state.duplicate(true)
	var target: Dictionary = DeviceMotion.patrol_target(entity, delta, world)
	if target.is_empty():
		return {}
	var target_position: Vector2 = DeviceRegistry.vector(target.position)
	var motion: Vector2 = target_position - global_position
	if motion.length_squared() <= 0.0000001:
		return target
	var hit := KinematicCollision2D.new()
	if test_move(global_transform, motion, hit):
		if hit.get_collider() != player:
			return previous
		if player == null or player.test_move(player.global_transform, motion):
			return previous
	# sync_to_physics publishes the transform at the next physics synchronization.
	# The next advance reads that synced position; this step returns the validated target.
	global_position = target_position
	return target


func motion_state() -> Dictionary:
	return {"position": DeviceRegistry.pair(global_position)}
