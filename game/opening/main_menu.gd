extends Control

const OPENING_SCENE := "res://opening/opening.tscn"
const WORLD_SCENE := "res://world2.tscn"
const PROGRESS := preload("res://districts/story_progress.gd")
const MASTER_BUS := 0

var _save_path := PROGRESS.PATH
var _settings_path := "user://settings.cfg"

@onready var _start: Button = $Center/Menu/Buttons/Start
@onready var _continue: Button = $Center/Menu/Buttons/Continue
@onready var _restart: ConfirmationDialog = $Restart
@onready var _settings: AcceptDialog = $Settings
@onready var _volume: HSlider = $Settings/Options/Volume
@onready var _fullscreen: CheckButton = $Settings/Options/Fullscreen
@onready var _message: AcceptDialog = $Message


func _ready() -> void:
	_start.pressed.connect(_request_new_game)
	_continue.pressed.connect(_continue_game)
	$Center/Menu/Buttons/Settings.pressed.connect(_open_settings)
	$Center/Menu/Buttons/Quit.pressed.connect(get_tree().quit)
	_restart.confirmed.connect(_start_new_game)
	_restart.get_ok_button().text = "重新开始"
	_restart.get_cancel_button().text = "取消"
	_settings.confirmed.connect(_save_settings)
	_settings.get_ok_button().text = "应用"
	_message.get_ok_button().text = "返回"
	_continue.disabled = ConfigFile.new().load(_save_path) != OK
	_load_settings()
	_start.grab_focus()


func _request_new_game() -> void:
	if FileAccess.file_exists(_save_path):
		_restart.popup_centered()
	else:
		_open_scene(OPENING_SCENE)


func _start_new_game() -> void:
	var error := DirAccess.remove_absolute(ProjectSettings.globalize_path(_save_path))
	if error != OK and error != ERR_FILE_NOT_FOUND:
		_show_message("无法重置存档：%s" % error_string(error))
		return
	_open_scene(OPENING_SCENE)


func _continue_game() -> void:
	if ConfigFile.new().load(_save_path) != OK:
		_continue.disabled = true
		_show_message("没有可读取的调查进度。")
		return
	var world_scene := load(WORLD_SCENE) as PackedScene
	if world_scene == null:
		_show_message("无法载入归岸镇。")
		return
	var world = world_scene.instantiate()
	world._save_path = _save_path
	var error := get_tree().change_scene_to_node(world)
	if error != OK:
		world.free()
		_show_message("无法续接调查：%s" % error_string(error))


func _open_scene(path: String) -> void:
	var error := get_tree().change_scene_to_file(path)
	if error != OK:
		_show_message("无法载入场景：%s" % error_string(error))


func _open_settings() -> void:
	_volume.value = 0.0 if AudioServer.is_bus_mute(MASTER_BUS) else AudioServer.get_bus_volume_linear(MASTER_BUS)
	_fullscreen.button_pressed = get_window().mode == Window.MODE_FULLSCREEN
	_settings.popup_centered()


func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(_settings_path) == OK:
		_apply_settings(clampf(float(config.get_value("audio", "volume", 1.0)), 0.0, 1.0),
			config.get_value("display", "fullscreen", false) == true)


func _save_settings() -> void:
	_apply_settings(_volume.value, _fullscreen.button_pressed)
	var config := ConfigFile.new()
	config.set_value("audio", "volume", _volume.value)
	config.set_value("display", "fullscreen", _fullscreen.button_pressed)
	var error := config.save(_settings_path)
	if error != OK:
		_show_message("无法保存设置：%s" % error_string(error))


func _apply_settings(volume: float, fullscreen: bool) -> void:
	AudioServer.set_bus_mute(MASTER_BUS, is_zero_approx(volume))
	AudioServer.set_bus_volume_linear(MASTER_BUS, maxf(volume, 0.001))
	var window := get_window()
	if fullscreen:
		window.mode = Window.MODE_FULLSCREEN
	elif window.mode == Window.MODE_FULLSCREEN:
		window.mode = Window.MODE_WINDOWED


func _show_message(message: String) -> void:
	_message.dialog_text = message
	_message.popup_centered()
