extends CharacterBody3D

@export var speed: float = 4.0

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
@onready var spawn_position := global_position


func _physics_process(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	var axes := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	var right := camera.global_basis.x
	var back := camera.global_basis.z
	right.y = 0.0
	back.y = 0.0
	var direction := right.normalized() * axes.x + back.normalized() * axes.y

	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	if is_on_floor() and direction.length_squared() > 0.01:
		_step_onto_landing(direction * speed * delta)
	if not is_on_floor():
		velocity.y -= gravity * delta
	move_and_slide()
	if absf(axes.x) > 0.1:
		$Traveller.flip_h = axes.x < 0

	if global_position.y < -2.0:
		global_position = spawn_position
		velocity = Vector3.ZERO


func _step_onto_landing(motion: Vector3) -> void:
	# The deck and stair are separate solids. Ease over a small vertical lip
	# only if the capsule can fit above it and a floor supports the next step.
	var hit := KinematicCollision3D.new()
	if not test_move(global_transform, motion, hit) or hit.get_normal().y > 0.45:
		return
	var lift := Vector3.UP * 0.28
	if test_move(global_transform, lift):
		return
	var raised := global_transform.translated(lift)
	if test_move(raised, motion):
		return
	if test_move(raised.translated(motion), -lift, hit) and hit.get_normal().y > cos(floor_max_angle):
		global_position.y += maxf(0.0, lift.y + hit.get_travel().y)
