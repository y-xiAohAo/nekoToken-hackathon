extends CharacterBody3D

signal attack_contact(origin: Vector3, direction: Vector3)
signal attack_swing(origin: Vector3, direction: Vector3)
signal attack_whiff
signal dodge_started(direction: Vector3)

const FACINGS: Array[StringName] = [&"e", &"se", &"s", &"sw", &"w", &"nw", &"n", &"ne"]
const COMBAT_SHEET := preload("res://actors/characters_2046_v2/william_combat.png")
const COMBAT := preload("res://districts/morning_star/combat_tuning.gd")

enum Action { NONE, PUNCH, DODGE, HURT }

@export var speed: float = 4.0
@export var run_speed: float = 6.4

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var facing: StringName = &"s"
var controls_locked := false
var combat_enabled := false
var _action := Action.NONE
var _action_time := 0.0
var _dodge_cooldown := 0.0
var _hurt_flash := 0.0
var _action_direction := Vector3.ZERO
var _punch_buffer := 0.0
var _dodge_buffer := 0.0
var _dodge_axis := Vector2.ZERO
var _contact_resolved := false
var _swing_started := false
var _hurt_grace := 0.0
var _hit_pause := 0.0

@onready var spawn_position := global_position
@onready var visual: AnimatedSprite3D = $Visual


func _ready() -> void:
	visual.sprite_frames = visual.sprite_frames.duplicate() as SpriteFrames
	var animations: Array[StringName] = [&"punch_side", &"punch_front", &"punch_back", &"dodge_side"]
	for row in range(animations.size()):
		var name_for_row := animations[row]
		visual.sprite_frames.add_animation(name_for_row)
		visual.sprite_frames.set_animation_loop(name_for_row, false)
		for column in range(6):
			var frame_texture := AtlasTexture.new()
			frame_texture.atlas = COMBAT_SHEET
			frame_texture.region = Rect2(column * 48, row * 48, 48, 48)
			visual.sprite_frames.add_frame(name_for_row, frame_texture)


func _physics_process(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	var axes := Vector2.ZERO if controls_locked else Input.get_vector(
		&"move_left", &"move_right", &"move_forward", &"move_back")
	var right := camera.global_basis.x.slide(Vector3.UP).normalized() if camera else Vector3.RIGHT
	var back := right.cross(Vector3.UP)
	if camera:
		# Keep the sprite upright for world depth, with square pixels in the camera view.
		var height_scale := 1.0 / maxf(camera.global_basis.y.y, 0.5)
		var recoil := 0.0
		if _action == Action.HURT:
			recoil = -_action_direction.dot(right) * 0.075 * (1.0 - minf(_action_time / COMBAT.HURT_STAGGER, 1.0))
		visual.global_basis = Basis(right, Vector3.UP * height_scale, back).rotated(back, recoil)
	var direction := right * axes.x + back * axes.y
	var running := Input.is_action_pressed(&"sprint")
	var move_speed := run_speed if running else speed

	var motion := direction * move_speed
	if combat_enabled and not controls_locked:
		motion = _combat_motion(delta, axes, right, back, motion)
	velocity.x = motion.x
	velocity.z = motion.z
	if not combat_enabled and is_on_floor() and motion.length_squared() > 0.01:
		_step_onto_landing(motion * delta)
	if not is_on_floor():
		velocity.y -= gravity * delta
	move_and_slide()
	if combat_enabled and not controls_locked and _action == Action.PUNCH and _hit_pause <= 0.0:
		_sample_punch_contact()

	if global_position.y < -2.0:
		respawn()
		return

	if _action == Action.NONE:
		_update_animation(axes, running)


func _input(event: InputEvent) -> void:
	if not combat_enabled or controls_locked:
		return
	if event.is_action_pressed(&"combat_attack"):
		_punch_buffer = COMBAT.INPUT_BUFFER
	elif event.is_action_pressed(&"combat_dodge"):
		_dodge_buffer = COMBAT.INPUT_BUFFER
		_dodge_axis = Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")


func set_combat_enabled(enabled: bool) -> void:
	combat_enabled = enabled
	_reset_combat_action()


func dodge_protects() -> bool:
	return _action == Action.DODGE and _action_time <= COMBAT.DODGE_INVUL


func can_take_combat_hit() -> bool:
	return not dodge_protects() and _hurt_grace <= 0.0


func resolve_contact() -> void:
	_contact_resolved = true


func pause_combat(seconds: float) -> void:
	_hit_pause = maxf(_hit_pause, seconds)


func take_combat_hit(direction: Vector3, push_scale := 1.0) -> void:
	_action_direction = direction.normalized() * push_scale
	_hurt_grace = COMBAT.HURT_GRACE
	_hurt_flash = COMBAT.HURT_FLASH
	_start_action(Action.HURT, StringName("idle_%s" % facing), false)
	visual.modulate = Color("#ff9b87")


func _combat_motion(delta: float, axes: Vector2, right: Vector3, back: Vector3,
		motion: Vector3) -> Vector3:
	# The poll also covers Input.action_press used by automated play and gamepads.
	if Input.is_action_just_pressed(&"combat_attack"):
		_punch_buffer = COMBAT.INPUT_BUFFER
	if Input.is_action_just_pressed(&"combat_dodge"):
		_dodge_buffer = COMBAT.INPUT_BUFFER
		_dodge_axis = axes
	if _hit_pause > 0.0:
		_hit_pause = maxf(0.0, _hit_pause - delta)
		if _hit_pause < 0.00001:
			_hit_pause = 0.0
		return Vector3.ZERO
	_dodge_cooldown = maxf(_dodge_cooldown - delta, 0.0)
	_hurt_grace = maxf(_hurt_grace - delta, 0.0)
	_hurt_flash = maxf(_hurt_flash - delta, 0.0)
	visual.modulate = Color.WHITE.lerp(Color("#ff9b87"), _hurt_flash / COMBAT.HURT_FLASH)
	if _action != Action.NONE and _action_time >= _action_duration():
		_end_action()
	if _dodge_buffer > 0.0 and _dodge_cooldown == 0.0 and _can_dodge_cancel():
		var dodge_axes := (axes if not axes.is_zero_approx() else _dodge_axis).normalized()
		if dodge_axes.is_zero_approx():
			var aim := Vector2.from_angle(float(FACINGS.find(facing)) * TAU / 8.0)
			dodge_axes = Vector2(aim.y, -aim.x)
		_action_direction = right * dodge_axes.x + back * dodge_axes.y
		_dodge_cooldown = COMBAT.DODGE_COOLDOWN
		_dodge_buffer = 0.0
		_start_action(Action.DODGE, &"dodge_side", dodge_axes.x < -0.05)
		dodge_started.emit(_action_direction)
	elif _punch_buffer > 0.0 and _can_punch_cancel():
		_punch_buffer = 0.0
		if not axes.is_zero_approx():
			facing = FACINGS[posmod(roundi(axes.angle() * 8.0 / TAU), FACINGS.size())]
		var aim := Vector2.from_angle(float(FACINGS.find(facing)) * TAU / 8.0)
		_action_direction = right * aim.x + back * aim.y
		var animation := &"punch_side"
		if aim.y < -0.60:
			animation = &"punch_back"
		elif facing == &"s":
			animation = &"punch_front"
		_start_action(Action.PUNCH, animation, aim.x < -0.05)

	_punch_buffer = maxf(0.0, _punch_buffer - delta)
	_dodge_buffer = maxf(0.0, _dodge_buffer - delta)
	if _action == Action.NONE:
		return motion
	_action_time += delta
	match _action:
		Action.PUNCH:
			visual.frame = _punch_frame()
			if _action_time >= COMBAT.PUNCH_MOVE_CANCEL and not axes.is_zero_approx() and _punch_buffer <= 0.0:
				_end_action()
				return motion
			if _action_time >= COMBAT.PUNCH_HIT_START * 0.62 and _action_time <= COMBAT.PUNCH_HIT_END:
				return _action_direction * COMBAT.PUNCH_LUNGE_SPEED
			return motion * (0.30 if _action_time >= COMBAT.PUNCH_HIT_END else 0.0)
		Action.DODGE:
			visual.frame = mini(5, int(_action_time * 6.0 / COMBAT.DODGE_DURATION))
			return _action_direction * COMBAT.DODGE_SPEED * (1.0 - 0.52 * minf(_action_time / COMBAT.DODGE_DURATION, 1.0))
		Action.HURT:
			return _action_direction * COMBAT.HURT_PUSH * maxf(0.0, 1.0 - _action_time / COMBAT.HURT_STAGGER)
	return motion


func _sample_punch_contact() -> void:
	if _action_time < COMBAT.PUNCH_HIT_START:
		return
	if not _swing_started:
		_swing_started = true
		attack_swing.emit(global_position, _action_direction)
	if _contact_resolved:
		return
	if _action_time <= COMBAT.PUNCH_HIT_END:
		attack_contact.emit(global_position, _action_direction)
	else:
		_contact_resolved = true
		attack_whiff.emit()


func _can_dodge_cancel() -> bool:
	return _action == Action.NONE or (_action == Action.PUNCH and _action_time >= COMBAT.PUNCH_DODGE_CANCEL)


func _can_punch_cancel() -> bool:
	return _action == Action.NONE or (_action == Action.PUNCH and _action_time >= COMBAT.PUNCH_CHAIN) \
		or (_action == Action.DODGE and _action_time >= COMBAT.DODGE_RECOVER)


func _action_duration() -> float:
	match _action:
		Action.PUNCH: return COMBAT.PUNCH_DURATION
		Action.DODGE: return COMBAT.DODGE_DURATION
		Action.HURT: return COMBAT.HURT_STAGGER
	return 0.0


func _punch_frame() -> int:
	if _action_time < COMBAT.PUNCH_HIT_START:
		return mini(2, int(_action_time / COMBAT.PUNCH_HIT_START * 3.0))
	if _action_time <= COMBAT.PUNCH_HIT_END:
		return 3
	return 4 if _action_time < COMBAT.PUNCH_CHAIN else 5


func _start_action(action: Action, animation: StringName, flip: bool) -> void:
	_action = action
	_action_time = 0.0
	_contact_resolved = false
	_swing_started = false
	visual.pause()
	visual.animation = animation
	visual.flip_h = flip
	visual.frame = 0


func _end_action() -> void:
	_action = Action.NONE
	_action_time = 0.0
	visual.flip_h = false


func _reset_combat_action() -> void:
	_punch_buffer = 0.0
	_dodge_buffer = 0.0
	_dodge_axis = Vector2.ZERO
	_dodge_cooldown = 0.0
	_hurt_flash = 0.0
	_hurt_grace = 0.0
	_hit_pause = 0.0
	visual.modulate = Color.WHITE
	_end_action()
	_update_animation(Vector2.ZERO, false)


func respawn() -> void:
	move_to(spawn_position)


func move_to(destination: Vector3) -> void:
	global_position = destination
	velocity = Vector3.ZERO
	reset_physics_interpolation()
	_reset_combat_action()


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
	var old_animation := String(visual.animation)
	var keep_phase := moving and (old_animation.begins_with("walk_") or old_animation.begins_with("run_"))
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
