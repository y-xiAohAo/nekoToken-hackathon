extends Node3D

const FOLLOW_OFFSET := Vector3(8.0, 17.0, 19.0)
const OVERVIEW_OFFSET := Vector3(22.0, 48.0, 55.0)

var overview := false
var cool_style := false
var interactables: Array[Node3D] = []
var nearby: Node3D
var notice := ""
var notice_time := 0.0

@onready var player: CharacterBody3D = $Player
@onready var camera: Camera3D = $Camera
@onready var sun: DirectionalLight3D = $Sun
@onready var world_environment: WorldEnvironment = $WorldEnvironment
@onready var status: Label = $HUD/Status
@onready var prompt: Label = $HUD/Prompt


func _ready() -> void:
	_apply_style()
	for unit in get_tree().get_nodes_in_group("world2_units"):
		if str(unit.get("interaction_name")) != "":
			interactables.append(unit)
	_update_camera(1.0)


func _process(delta: float) -> void:
	_update_camera(1.0 - exp(-6.0 * delta))
	notice_time = maxf(0.0, notice_time - delta)
	_update_interaction()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.physical_keycode:
		KEY_TAB:
			overview = not overview
		KEY_V:
			cool_style = not cool_style
			_apply_style()
		KEY_R:
			player.global_position = player.spawn_position
			player.velocity = Vector3.ZERO
		KEY_E:
			if nearby != null:
				notice = "已查看：" + str(nearby.get("interaction_name"))
				notice_time = 2.5


func _apply_style() -> void:
	for unit in get_tree().get_nodes_in_group("world2_units"):
		unit.district = 1 if cool_style else 0
	sun.light_color = Color("#e5f3ff") if cool_style else Color("#ffd6ab")
	sun.light_energy = 0.82 if cool_style else 0.72
	world_environment.environment.ambient_light_color = Color("#dcefff") if cool_style else Color("#b0bac2")
	world_environment.environment.ambient_light_energy = 0.65 if cool_style else 0.5
	status.text = ("M镇配色预览" if cool_style else "蚁穴贴图版") + "  |  26 × 18 格 / 52 × 36 米"


func _update_camera(weight: float) -> void:
	var focus := Vector3.ZERO if overview else player.global_position + Vector3(0, 0.5, 0)
	var offset := OVERVIEW_OFFSET if overview else FOLLOW_OFFSET
	camera.position = camera.position.lerp(focus + offset, weight)
	camera.look_at(focus)
	camera.size = lerpf(camera.size, 45.0 if overview else 12.5, weight)


func _update_interaction() -> void:
	nearby = null
	var nearest := 4.0
	for unit in interactables:
		var distance := player.global_position.distance_squared_to(unit.global_position)
		if distance < nearest:
			nearest = distance
			nearby = unit
	if notice_time > 0.0:
		prompt.text = notice
	elif nearby != null:
		prompt.text = "E  查看 " + str(nearby.get("interaction_name"))
	else:
		prompt.text = ""
