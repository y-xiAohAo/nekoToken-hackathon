extends Sprite3D

@export var face_travel := false
@export var walk_texture: Texture2D
@export_range(0.5, 2.0, 0.05, "suffix:m") var walk_cycle_distance := 1.1
@export_range(0.0, 85.0, 1.0) var sweep_half_angle := 65.0
@export_range(1.0, 30.0, 0.1, "suffix:s") var sweep_period := 6.0

var _atlas: AtlasTexture
var _idle_texture: Texture2D
var _previous_position: Vector3
var _facing: Vector3
var _sweep_phase := 0.0
var _walk_distance := 0.0
var _moving := false

@onready var _body := get_parent() as Node3D


func _ready() -> void:
	_atlas = (texture as AtlasTexture).duplicate() as AtlasTexture
	_idle_texture = _atlas.atlas
	texture = _atlas
	billboard = BaseMaterial3D.BILLBOARD_DISABLED
	_previous_position = _body.global_position
	_facing = -_body.global_basis.z if face_travel else _body.global_basis.z
	set_physics_process(face_travel)


func _physics_process(_delta: float) -> void:
	var current := _body.global_position
	var motion := current - _previous_position
	_previous_position = current
	var distance := motion.length()
	_moving = distance > 0.001
	if _moving:
		_facing = motion
		_walk_distance = fposmod(_walk_distance + distance, walk_cycle_distance)
	else:
		_walk_distance = 0.0


func _process(delta: float) -> void:
	if not face_travel:
		_sweep_phase = fposmod(_sweep_phase + delta / sweep_period, 1.0)
		var yaw := deg_to_rad(sweep_half_angle) * sin(_sweep_phase * TAU)
		_facing = _body.global_basis.z.rotated(Vector3.UP, yaw)

	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var right := camera.global_basis.x.slide(Vector3.UP).normalized()
	var back := right.cross(Vector3.UP)
	var height_scale := 1.0 / maxf(camera.global_basis.y.y, 0.5)
	global_basis = Basis(right, Vector3.UP * height_scale, back)

	var side := _facing.dot(right)
	var depth := _facing.dot(back)
	var sideways := absf(side) > absf(depth)
	var region := _atlas.region
	var next_texture := _idle_texture
	if _moving and sideways and walk_texture != null:
		next_texture = walk_texture
		var frame_count := int(walk_texture.get_width() / region.size.x)
		var frame := floori(_walk_distance / walk_cycle_distance * frame_count)
		region.position.x = frame * region.size.x
	else:
		region.position.x = region.size.x if sideways else (0.0 if depth >= 0.0 else region.size.x * 2.0)
	if _atlas.atlas != next_texture:
		_atlas.atlas = next_texture
	if _atlas.region != region:
		_atlas.region = region
	flip_h = sideways and side < 0.0
