extends CharacterBody3D

@export_range(0.5, 40.0, 0.1, "suffix:m") var patrol_distance := 8.0
@export_range(0.1, 8.0, 0.1, "suffix:m/s") var patrol_speed := 2.2
@export_range(0.0, 5.0, 0.1, "suffix:s") var turnaround_wait := 0.45

var _start: Vector3
var _end: Vector3
var _heading_to_end := true
var _wait_left := 0.0


func _ready() -> void:
	_start = global_position
	var forward := -global_basis.z.slide(Vector3.UP).normalized()
	_end = _start + forward * patrol_distance


func _physics_process(delta: float) -> void:
	if _wait_left > 0.0:
		_wait_left = maxf(0.0, _wait_left - delta)
		return

	var finish := _end if _heading_to_end else _start
	var displacement := finish - global_position
	if displacement.length_squared() <= 0.0001:
		_heading_to_end = not _heading_to_end
		_wait_left = turnaround_wait
		return

	# A blocker stops the patrol on its track until the lane clears.
	move_and_collide(displacement.limit_length(patrol_speed * delta))
