extends Node3D

const TOWN := preload("res://districts/mtown/modular_town.tscn")
const UI := preload("res://districts/interaction_ui.gd")
const ACTOR := preload("res://actors/story_actor.gd")
const PEOPLE := preload("res://districts/npc_dialogue.gd").DIALOGUE
const SAVE_PATH := "user://story_progress.cfg"
const DRAWER_ITEMS: Array[String] = ["carl_interview", "trip_leaflet"]
const MAP_NAMES: Array[String] = ["蚁穴 · 归岸镇", "明日镇"]
const CAMERA_ROTATION := Vector3(-45.0, 0.0, 0.0)

var overview := false
var overview_progress := 0.0
var map_index := 0
var props: Dictionary = {}
var collected: Dictionary = {}
var _textures: Dictionary = {}
var _maps: Array[Node3D] = []
var _targets: Array[Marker3D] = []
var _nearby: Marker3D
var _ui: UI
var _save_path := SAVE_PATH

@onready var player = $Player
@onready var camera: Camera3D = $Camera
@onready var sun: DirectionalLight3D = $Sun
@onready var world_environment: WorldEnvironment = $WorldEnvironment
@onready var status: Label = $HUD/Status
@onready var map_mount: Node3D = $MapMount


func _ready() -> void:
	_load_props()
	_load_progress()
	_ui = UI.new()
	_ui.name = "StoryUI"
	add_child(_ui)
	_ui.closed.connect(_unlock_controls)
	_maps = [map_mount.get_node("Guian") as Node3D, null]
	_prepare_district(_maps[0])
	_activate_targets(_maps[0])
	_set_style()
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.rotation_degrees = CAMERA_ROTATION
	_update_camera()


func _exit_tree() -> void:
	for district in _maps:
		if is_instance_valid(district) and district.get_parent() == null:
			district.free()


func _process(delta: float) -> void:
	overview_progress = move_toward(overview_progress, 1.0 if overview else 0.0, delta * 4.0)
	_update_camera()
	_update_interaction()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	var key := (event as InputEventKey).physical_keycode
	if _ui.is_open():
		if key == KEY_ESCAPE or event.is_action_pressed("interact"):
			_ui.close()
		elif key >= KEY_1 and key <= KEY_9:
			_ui.choose(key - KEY_1)
		get_viewport().set_input_as_handled()
		return
	match key:
		KEY_TAB:
			overview = not overview
		KEY_1:
			_switch_map(0)
		KEY_2:
			_switch_map(1)
		KEY_R:
			player.respawn()
			_update_camera()
		_:
			if event.is_action_pressed("interact") and is_instance_valid(_nearby):
				_interact(_nearby)


func _switch_map(index: int) -> void:
	if index == map_index:
		return
	_ui.close()
	_nearby = null
	map_mount.remove_child(_maps[map_index])
	var first_visit := _maps[index] == null
	if first_visit:
		_maps[index] = TOWN.instantiate() as Node3D
	map_index = index
	var district := _maps[index]
	map_mount.add_child(district)
	if first_visit:
		_prepare_district(district)
	_activate_targets(district)
	var spawn := district.get_node("Markers/Spawn") as Marker3D
	player.spawn_position = spawn.global_position
	player.respawn()
	_set_style()
	_update_camera()


func _set_style() -> void:
	var city := map_index == 1
	sun.light_color = Color("#edf5ff") if city else Color("#ffd6ab")
	sun.light_energy = 0.64 if city else 0.72
	world_environment.environment.ambient_light_color = Color("#a9c0db") if city else Color("#b0bac2")
	world_environment.environment.ambient_light_energy = 0.40 if city else 0.5
	world_environment.environment.background_color = Color("#111f36") if city else Color("#1b2430")
	_update_status()


func _update_camera() -> void:
	var actor_position: Vector3 = player.get_global_transform_interpolated().origin
	var blend := smoothstep(0.0, 1.0, overview_progress)
	var focus := (actor_position + Vector3(0, 0.5, 0)).lerp(Vector3.ZERO, blend)
	camera.size = lerpf(12.5, 39.0, blend)
	var viewport_size := get_viewport().get_visible_rect().size
	var horizontal_half_span := camera.size * 0.5 * viewport_size.aspect()
	var x_limit := maxf(0.0, 27.25 - horizontal_half_span)
	focus.x = clampf(focus.x, -x_limit, x_limit)
	camera.global_position = focus + camera.global_basis.z * lerpf(30.0, 78.0, blend)


func _prepare_district(district: Node3D) -> void:
	for child in district.get_node("Markers").get_children():
		var marker := child as Marker3D
		var id := String(marker.name)
		var offset: Vector3 = marker.get_meta("display_offset", Vector3.ZERO)
		if id.begins_with("npc_"):
			var person: Dictionary = PEOPLE[id.trim_prefix("npc_")]
			var actor := ACTOR.new()
			actor.name = "Actor"
			actor.configure(person.scene, player)
			marker.add_child(actor)
		elif props.has(id):
			# The gate sign is already represented by the physical sign in the level.
			if id != "guian_sign":
				_add_world_icon(marker, id, offset)
		elif id == "drawer":
			_add_world_icon(marker, DRAWER_ITEMS[0], offset)
		elif id == "Portal":
			var exit_label := Label3D.new()
			exit_label.text = "↗"
			exit_label.no_depth_test = false
			exit_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			exit_label.font_size = 46
			exit_label.font = status.get_theme_font("font")
			exit_label.pixel_size = 0.015
			exit_label.modulate = Color("#d0eeff")
			exit_label.position = offset
			marker.add_child(exit_label)


func _add_world_icon(marker: Marker3D, id: String, offset: Vector3) -> void:
	var texture := _prop_texture(id)
	if texture == null:
		return
	var icon := Sprite3D.new()
	icon.texture = texture
	icon.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	icon.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	icon.pixel_size = 0.68 / float(maxi(texture.get_width(), texture.get_height()))
	icon.position = offset
	icon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.add_child(icon)


func _activate_targets(district: Node3D) -> void:
	_targets.clear()
	for child in district.get_node("Markers").get_children():
		if child.name != &"Spawn":
			_targets.append(child as Marker3D)


func _update_interaction() -> void:
	_nearby = null
	if _ui.is_open() or overview_progress >= 0.55:
		_ui.show_hint("", Vector2.ZERO)
		return

	var closest := INF
	for marker in _targets:
		var id := String(marker.name)
		var delta: Vector3 = marker.global_position - player.global_position
		var radius := 2.15 if id.begins_with("npc_") else 1.54
		if absf(delta.y) > 0.58:
			continue
		var distance := delta.length_squared()
		if distance < minf(closest, radius * radius):
			_nearby = marker
			closest = distance
	if _nearby == null:
		_ui.show_hint("", Vector2.ZERO)
		return

	var height := 1.24 if String(_nearby.name).begins_with("npc_") else 1.0
	var position_on_screen := camera.unproject_position(_nearby.global_position + Vector3.UP * height)
	_ui.show_hint(_prompt_for(String(_nearby.name)), position_on_screen)


func _prompt_for(id: String) -> String:
	if id == "Portal":
		return "前往" + MAP_NAMES[1 - map_index]
	if id == "drawer":
		return "打开门边柜"
	if id.begins_with("npc_"):
		return "与%s交谈" % PEOPLE[id.trim_prefix("npc_")].name
	return "查看" + String(props[id].name)


func _interact(marker: Marker3D) -> void:
	var id := String(marker.name)
	if id == "Portal":
		_switch_map(1 - map_index)
		return
	if id == "drawer":
		_open_drawer()
	elif id.begins_with("npc_"):
		_open_dialogue(id.trim_prefix("npc_"))
	else:
		_open_prop(id)


func _open_drawer() -> void:
	player.controls_locked = true
	var options: Array[String] = ["查看旧手机", "翻开毕业旅行折页"]
	_ui.open_conversation("贾斯珀的门边柜", "柜子里有一部旧手机，旁边压着一张折过的纸。", options,
		func(index: int) -> void: _open_prop(DRAWER_ITEMS[index]))


func _open_prop(id: String) -> void:
	if not collected.has(id):
		collected[id] = true
		_save_progress()
		_update_status()
	player.controls_locked = true
	_ui.open_prop(props[id], _prop_texture(id), collected.size(), props.size())


func _open_dialogue(id: String) -> void:
	player.controls_locked = true
	var person: Dictionary = PEOPLE[id]
	var options: Array[String] = []
	for topic in person.topics:
		options.append(topic[0])
	_ui.open_conversation(person.name, person.greeting, options,
		func(index: int) -> void: _open_reply(id, index))


func _open_reply(id: String, index: int) -> void:
	var person: Dictionary = PEOPLE[id]
	var options: Array[String] = ["再问一件事"]
	_ui.open_conversation(person.name, person.topics[index][1], options,
		func(_selected: int) -> void: _open_dialogue(id))


func _unlock_controls() -> void:
	player.controls_locked = false


func _update_status() -> void:
	status.text = "%s  |  道具  %02d / %02d" % [MAP_NAMES[map_index], collected.size(), props.size()]


func _load_props() -> void:
	var entries: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://props/props.json"))
	if not entries is Array:
		push_error("无法读取道具清单 res://props/props.json")
		return
	for entry in entries:
		props[entry.id] = entry


func _prop_texture(id: String) -> Texture2D:
	if not _textures.has(id):
		var path := "res://props/%s" % props[id].image
		_textures[id] = load(path) as Texture2D
	return _textures[id]


func _load_progress() -> void:
	var save := ConfigFile.new()
	if save.load(_save_path) == OK:
		var ids: Variant = save.get_value("collection", "items", [])
		if ids is Array:
			for id in ids:
				if props.has(id):
					collected[id] = true


func _save_progress() -> void:
	var save := ConfigFile.new()
	save.set_value("collection", "items", collected.keys())
	var error := save.save(_save_path)
	if error != OK:
		push_warning("道具收集进度写入失败：%s" % error_string(error))
