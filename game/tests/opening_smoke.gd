extends SceneTree

const OPENING := preload("res://opening/opening.gd")
const MENU := preload("res://opening/main_menu.gd")
const WORLD_PATH := "res://world2.tscn"

var _passed := 0
var _failed := 0
var _scratch := "res://.godot/menu-progress-%d.cfg" % OS.get_process_id()
var _settings := "res://.godot/menu-settings-%d.cfg" % OS.get_process_id()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var opening := await _start_opening()
	if opening == null:
		_finish()
		return
	_check(OPENING.PAGES.size() == 2 and opening._labels[0].visible_characters == 0,
		"opening starts on black before the first of two pages")
	_check(not opening._actions.is_visible_in_tree(), "the opening starts without bottom controls")
	var year := opening._labels[0]
	_check(await _frames_until_text(year, 1, 60) >= 0 and year.visible_characters == year.text.length(),
		"an emphasized line appears in full")
	var first_sentence := opening._labels[1]
	var pause := await _frames_until_text(first_sentence, 1, 115)
	_check(pause >= 95 and pause <= 102, "the first timed character follows the emphasized line by 1.6 seconds")
	_check(first_sentence.visible_characters > 0 and first_sentence.visible_characters < first_sentence.text.length(),
		"the narrative is revealed character by character")
	var typing_frames := await _frames_until_text(first_sentence, first_sentence.text.length(), 140)
	var expected_frames := roundi(first_sentence.text.length() * 0.09 * 60.0)
	_check(typing_frames >= expected_frames - 7 and typing_frames <= expected_frames + 2,
		"the first narrative sentence types at 0.09 seconds per character")
	var line_gap := await _frames_until_text(opening._labels[2], 1, 10)
	_check(line_gap >= 0 and line_gap <= 7, "ordinary typed sentences have no added pause")
	_tap(KEY_ENTER)
	var last_world_line := opening._labels.back() as Label
	_check(last_world_line.visible_characters == last_world_line.text.length(), "Enter reveals the current passage")
	_check(await _advance_to(opening, 0, 1), "world introduction fades to its closing line")
	_check(opening._labels.size() == 1 and opening._labels[0].text == "人类便不再拥有同一个明天。",
		"the world page ends with its closing line alone")
	_check(await _advance_to(opening, 1, 0), "the closing line fades before William's page")
	_check(opening._labels.size() == 4 and opening._labels[1].text == "2 天" and opening._labels[3].text == "1325 天"
		and opening._labels[1].get_theme_font_size("font_size") > opening._labels[0].get_theme_font_size("font_size"),
		"William's page emphasizes both missing-day counts")
	_check(await _advance_to(opening, 1, 1), "William's narration follows the two counts")
	_check(await _advance_to(opening, 1, 2), "William's promise appears after the narration")
	_check(opening._labels.back().text == "哥哥来接你回家。" and not opening._actions.is_visible_in_tree(),
		"the final passage still hides the entry button while it is playing")
	var first_promise := opening._labels[0]
	var last_promise := opening._labels[1]
	_check(await _frames_until_text(first_promise, 1, 15) >= 0
		and first_promise.visible_characters == first_promise.text.length(), "William's first promise appears all at once")
	var promise_gap := await _frames_until_text(last_promise, 1, 115)
	_check(promise_gap >= 95 and promise_gap <= 97 and last_promise.visible_characters == last_promise.text.length(),
		"the final line appears in full exactly 1.6 seconds after the previous line")
	_check(not opening._actions.is_visible_in_tree(), "the button stays hidden until the final line's beat ends")
	_tap(KEY_ESCAPE)
	_check(await _wait_for_guian(90), "Escape skips the prologue and loads Guian")
	_check(await _check_reveal(), "skipping still fades from black into Guian")

	opening = await _start_opening()
	if opening != null:
		_check(await _wait_for_button(opening), "uninterrupted playback shows one entry button after the last line")
		for _frame in range(60):
			await process_frame
		_check(current_scene == opening, "the game waits for the player to enter Guian")
		_click(opening._enter_button)
		_check(await _wait_for_guian(90), "the entry button loads Guian")
		_check(await _check_reveal(), "the full prologue fades into Guian and removes the transition overlay")
	await _check_menu_actions()
	_finish()


func _start_opening() -> OPENING:
	var menu := await _start_menu()
	if menu == null:
		return null
	_check(menu._continue.disabled, "Continue is disabled without an existing investigation")
	await process_frame
	_click(menu._start)
	for _frame in range(90):
		if current_scene is OPENING:
			_check(true, "Start Investigation opens the prologue")
			return current_scene as OPENING
		await process_frame
	_check(false, "Start Investigation opens the prologue")
	return null


func _start_menu() -> MENU:
	var entry: String = ProjectSettings.get_setting("application/run/main_scene")
	var packed := load(entry) as PackedScene
	var menu := packed.instantiate() as MENU if packed != null else null
	_check(menu != null, "the project launches at the title menu")
	if menu == null:
		return null
	menu._save_path = _scratch
	menu._settings_path = _settings
	if change_scene_to_node(menu) != OK:
		menu.free()
		_check(false, "project entry scene loads")
		return null
	await scene_changed
	return menu


func _check_menu_actions() -> void:
	var save := ConfigFile.new()
	save.set_value("collection", "items", ["hospital_receipt", "usb_airship_audio"])
	if save.save(_scratch) != OK:
		_check(false, "built a temporary save for menu tests")
		return
	var menu := await _start_menu()
	if menu == null:
		return
	_check(not menu._continue.disabled, "Continue is available with an existing save")
	menu._open_settings()
	menu._volume.value = 0.45
	menu._settings.get_ok_button().pressed.emit()
	var settings := ConfigFile.new()
	_check(settings.load(_settings) == OK and is_equal_approx(settings.get_value("audio", "volume", 0.0), 0.45),
		"Settings applies and saves the master volume")
	menu._start.pressed.emit()
	_check(menu._restart.visible and FileAccess.file_exists(_scratch), "starting over asks before resetting progress")
	menu._restart.hide()
	menu._continue.pressed.emit()
	if await _wait_for_guian(90):
		_check(current_scene.collected.size() == 2 and current_scene._guian_cleared(),
			"Continue enters Guian with the existing chapter progress")
	else:
		_check(false, "Continue reaches Guian")
	menu = await _start_menu()
	if menu == null:
		return
	menu._start.pressed.emit()
	menu._restart.get_ok_button().pressed.emit()
	for _frame in range(90):
		if current_scene is OPENING:
			break
		await process_frame
	_check(current_scene is OPENING and not FileAccess.file_exists(_scratch),
		"confirming a new investigation resets the temporary save and opens the prologue")


func _tap(key: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = key
		event.physical_keycode = key
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()


func _advance_to(opening: OPENING, page: int, part: int) -> bool:
	_tap(KEY_ENTER)
	for _frame in range(125):
		if opening._page == page and opening._part == part:
			return true
		await process_frame
	return false


func _frames_until_text(label: Label, characters: int, frame_limit: int) -> int:
	for frame in range(frame_limit):
		if label.visible_characters >= characters:
			return frame
		await process_frame
	return -1


func _wait_for_button(opening: OPENING) -> bool:
	for _frame in range(4000):
		if not is_instance_valid(opening):
			return false
		if opening._actions.is_visible_in_tree():
			var last_line := opening._labels.back() as Label
			return opening._is_final_part() and last_line.visible_characters == last_line.text.length() \
				and opening._actions.get_child_count() == 1 and opening._enter_button.text == "进入归岸镇"
		await process_frame
	return false


func _click(button: Button) -> void:
	var center := button.get_global_transform_with_canvas() * (button.size * 0.5)
	var motion := InputEventMouseMotion.new()
	motion.position = center
	motion.global_position = center
	root.push_input(motion, true)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = center
		event.global_position = center
		event.pressed = pressed
		root.push_input(event, true)


func _check_reveal() -> bool:
	var reveal := root.get_node_or_null("OpeningReveal") as OPENING.DistrictReveal
	if reveal == null or reveal._black.color.a < 0.9:
		return false
	for _frame in range(90):
		await process_frame
	if not is_instance_valid(reveal) or reveal._black.color.a <= 0.0 or reveal._black.color.a >= 0.9:
		return false
	for _frame in range(105):
		await process_frame
	return not is_instance_valid(reveal)


func _wait_for_guian(frame_limit: int) -> bool:
	for _frame in range(frame_limit):
		if is_instance_valid(current_scene) and current_scene.scene_file_path == WORLD_PATH:
			return current_scene.has_node("MapMount/Guian") and current_scene.map_index == 0
		await process_frame
	return false


func _check(condition: bool, description: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		push_error("FAIL: " + description)


func _finish() -> void:
	for path in [_scratch, _settings]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("opening smoke: %d passed, %d failed" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)
