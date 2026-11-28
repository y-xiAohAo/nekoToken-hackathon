extends Node3D

signal target_spotted(target: Node3D)
signal target_lost(target: Node3D)

@export_range(0.0, 135.0, 1.0) var sweep_half_angle := 55.0
@export_range(1.0, 30.0, 0.1, "suffix:s") var sweep_period := 7.0
@export_range(1.0, 30.0, 0.1, "suffix:m") var sight_range := 9.0
@export_range(10.0, 150.0, 1.0) var horizontal_fov := 62.0
@export_range(10.0, 150.0, 1.0) var vertical_fov := 50.0
@export_flags_3d_physics var occlusion_mask := 1

var _phase := 0.0
var _tracked: Node3D
var _active_target: Node3D

@onready var _swivel: Node3D = $Swivel
@onready var _lens: Marker3D = $Swivel/Head/Lens
@onready var _indicator: StandardMaterial3D = $Swivel/Head/Indicator.material_override


func _physics_process(delta: float) -> void:
	var period := maxf(sweep_period, 0.1)
	_phase = fposmod(_phase + delta / period, 1.0)
	_swivel.rotation.y = sin(_phase * TAU) * deg_to_rad(sweep_half_angle)

	if not is_instance_valid(_tracked):
		_tracked = get_tree().get_first_node_in_group(&"surveillance_targets") as Node3D
	var visible_target: Node3D = _tracked if is_instance_valid(_tracked) and can_see(_tracked) else null
	if visible_target != _active_target:
		_update_indicator(visible_target)


func can_see(target: Node3D) -> bool:
	var point := target.global_position + Vector3.UP * 0.9
	var local := _lens.to_local(point)
	var depth := -local.z
	if depth <= 0.0 or local.length_squared() > sight_range * sight_range:
		return false
	if absf(local.x) > depth * tan(deg_to_rad(horizontal_fov * 0.5)):
		return false
	if absf(local.y) > depth * tan(deg_to_rad(vertical_fov * 0.5)):
		return false

	var ray := PhysicsRayQueryParameters3D.create(_lens.global_position, point, occlusion_mask)
	if target is CollisionObject3D:
		ray.exclude = [target.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(ray).is_empty()


func _update_indicator(visible_target: Node3D) -> void:
	var previous := _active_target
	_active_target = visible_target
	var tint := Color("#ffb86d") if visible_target != null else Color("#5de3ff")
	_indicator.albedo_color = tint
	_indicator.emission = tint
	if is_instance_valid(previous):
		target_lost.emit(previous)
	if is_instance_valid(visible_target):
		target_spotted.emit(visible_target)
