extends CharacterBody3D

const FACINGS: Array[StringName] = [&"e", &"se", &"s", &"sw", &"w", &"nw", &"n", &"ne"]

@export var speed: float = 4.0
@export var run_speed: float = 6.4

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var facing: StringName = &"s"
var controls_locked := false

@onready var spawn_position := global_position
@onready var visual: AnimatedSprite3D = $Visual


func _physics_process(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	var axes := Vector2.ZERO if controls_locked else Input.get_vector(
		&"move_left", &"move_right", &"move_forward", &"move_back")
	var right := camera.global_basis.x.slide(Vector3.UP).normalized() if camera else Vector3.RIGHT
	var back := right.cross(Vector3.UP)
	if camera:
		# Keep the sprite upright for world depth, with square pixels in the camera view.
		var height_scale := 1.0 / maxf(camera.global_basis.y.y, 0.5)
		visual.global_basis = Basis(right, Vector3.UP * height_scale, back)
	var direction := right * axes.x + back * axes.y
	var running := Input.is_action_pressed(&"sprint")
	var move_speed := run_speed if running else speed

	velocity.x = direction.x * move_speed
	velocity.z = direction.z * move_speed
	if is_on_floor() and direction.length_squared() > 0.01:
		_step_onto_landing(direction * move_speed * delta)
	if not is_on_floor():
		velocity.y -= gravity * delta
	move_and_slide()

	if global_position.y < -2.0:
		respawn()
		return

	_update_animation(axes, running)


func respawn() -> void:
	move_to(spawn_position)


func move_to(destination: Vector3) -> void:
	global_position = destination
	velocity = Vector3.ZERO
	reset_physics_interpolation()
	_update_animation(Vector2.ZERO, false)


func _update_animation(axes: Vector2, running: bool) -> void:
	if not axes.is_zero_approx():
		facing = FACINGS[posmod(roundi(axes.angle() * 8.0 / TAU), FACINGS.size())]

	var moving := (
		not axes.is_zero_approx()
		and is_on_floor()
		and get_real_velocity().slide(Vector3.UP).length_squared() > 0.01
	)
	var action := "run" if running else "walk"
	var animation := StringName("%s_%s" % [action if moving else "idle", facing])
	if visual.animation == animation:
		return

	# All locomotion tracks share the same six phases, so turns and speed changes keep the step.
	var keep_phase := moving and not String(visual.animation).begins_with("idle_")
	var previous_frame := visual.frame
	var previous_progress := visual.frame_progress
	visual.play(animation)
	if keep_phase:
		visual.set_frame_and_progress(previous_frame, previous_progress)


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
