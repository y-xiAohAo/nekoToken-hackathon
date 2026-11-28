extends CanvasLayer

const TUNE := preload("res://districts/morning_star/combat_tuning.gd")
const STAGE_LABELS: Array[String] = ["I  投影接管", "II  追击同步", "III  双重锁定"]
const BAR_TONES: Array[Color] = [Color("#e9ae65"), Color("#7cb9e5"), Color("#ac95ee")]

var _life: Label
var _boss_bar: ProgressBar
var _damage_bar: ProgressBar
var _opening: ProgressBar
var _health: Label
var _message: Label
var _keys: Label
var _stage := 1
var _last_life := 0
var _damage_tween: Tween
var _life_tween: Tween


func build(theme: Theme, boss_max: int, player_max: int) -> void:
	layer = 5
	var root := Control.new()
	root.theme = theme
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var heading := VBoxContainer.new()
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heading.add_theme_constant_override("separation", 4)
	root.add_child(heading)
	heading.anchor_left = 0.5
	heading.anchor_right = 0.5
	heading.offset_left = -213
	heading.offset_right = 213
	heading.offset_top = 14

	heading.add_child(_label("海普与晨星", 23, Color("#dbf5f7")))
	var meter := Control.new()
	meter.custom_minimum_size.y = 13.0
	meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heading.add_child(meter)
	_damage_bar = _progress(boss_max)
	_damage_bar.add_theme_stylebox_override("background", _bar_style(Color("#192b3a"), Color("#355567")))
	_damage_bar.add_theme_stylebox_override("fill", _bar_style(Color("#d86c64"), Color("#f2968a")))
	meter.add_child(_damage_bar)
	_damage_bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_boss_bar = ProgressBar.new()
	_boss_bar.name = "BossHealth"
	_boss_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_bar.show_percentage = false
	_boss_bar.max_value = boss_max
	_boss_bar.custom_minimum_size.y = 13.0
	_boss_bar.add_theme_stylebox_override("background", StyleBoxEmpty.new())
	meter.add_child(_boss_bar)
	_boss_bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for threshold in [TUNE.TIER_THREE_HP, TUNE.TIER_TWO_HP]:
		var tick := ColorRect.new()
		tick.color = Color("#152232c7")
		tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
		meter.add_child(tick)
		tick.anchor_left = float(threshold) / boss_max
		tick.anchor_right = tick.anchor_left
		tick.anchor_bottom = 1.0
		tick.offset_left = -0.5
		tick.offset_right = 0.5
		tick.offset_top = 1.0
		tick.offset_bottom = -1.0
	_health = _label("", 14, Color("#a2b9cb"))
	heading.add_child(_health)

	_life = _label("", 18, Color("#a6edf1"))
	_life.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	root.add_child(_life)
	_life.anchor_top = 1.0
	_life.anchor_bottom = 1.0
	_life.offset_left = 19
	_life.offset_top = -43
	_life.offset_bottom = -14

	var footer := VBoxContainer.new()
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	footer.add_theme_constant_override("separation", 3)
	root.add_child(footer)
	footer.anchor_left = 0.5
	footer.anchor_right = 0.5
	footer.anchor_top = 1.0
	footer.anchor_bottom = 1.0
	footer.offset_left = -330
	footer.offset_right = 330
	footer.offset_top = -76
	footer.offset_bottom = -13
	_message = _label("", 20, Color("#ffd69f"))
	_message.custom_minimum_size.y = 28
	footer.add_child(_message)
	_opening = _progress(1.0)
	_opening.step = 0.0
	_opening.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_opening.custom_minimum_size = Vector2(110, 4)
	_opening.add_theme_stylebox_override("background", StyleBoxEmpty.new())
	_opening.add_theme_stylebox_override("fill", _bar_style(Color("#70dbe6"), Color("#9bf2f4")))
	footer.add_child(_opening)
	_keys = _label("", 16, Color("#a8c2d5"))
	footer.add_child(_keys)
	set_stage(1)
	set_health(boss_max, player_max, player_max)
	set_finished(false)
	set_opening(0.0)


func set_health(boss_hp: int, player_hp: int, player_max: int) -> void:
	var before := _boss_bar.value
	_boss_bar.value = boss_hp
	if before != boss_hp:
		if _damage_tween:
			_damage_tween.kill()
		if boss_hp < before:
			_damage_bar.value = maxf(before, _damage_bar.value)
			_damage_tween = create_tween()
			_damage_tween.tween_property(_damage_bar, "value", float(boss_hp), 0.34).set_delay(0.095)
		else:
			_damage_bar.value = boss_hp
	_refresh_boss_text()
	_life.text = "威廉  " + "■ ".repeat(player_hp) + "□ ".repeat(player_max - player_hp)
	if _life_tween:
		_life_tween.kill()
	var tone := Color("#ffb587") if player_hp == 1 else Color("#a6edf1")
	_life.add_theme_color_override("font_color", tone)
	_life.modulate = Color.WHITE
	if player_hp < _last_life:
		_life.modulate = Color("#ff7c6a")
		_life_tween = create_tween()
		_life_tween.tween_property(_life, "modulate", Color.WHITE, 0.32)
	_last_life = player_hp


func set_stage(stage: int) -> void:
	_stage = stage
	var tone := BAR_TONES[stage - 1]
	_boss_bar.add_theme_stylebox_override("fill", _bar_style(tone, tone.lightened(0.34)))
	_refresh_boss_text()


func set_opening(amount: float) -> void:
	_opening.value = amount
	_opening.visible = amount > 0.0


func _refresh_boss_text() -> void:
	_health.text = "%s    %d / %d" % [STAGE_LABELS[_stage - 1], int(_boss_bar.value), int(_boss_bar.max_value)]


func set_message(message: String) -> void:
	_message.text = message


func set_finished(finished: bool) -> void:
	_life.show()
	_keys.show()
	_keys.text = "R 重试   E 返回办公室" if finished else (
		"WASD 移动   Shift 快速移动   J 攻击   K 侧闪   Esc 返回")


func begin_cinematic() -> void:
	_life.hide()
	_keys.hide()
	set_opening(0.0)


func _label(value: String, size: int, ink: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", ink)
	return label


func _progress(maximum: float) -> ProgressBar:
	var result := ProgressBar.new()
	result.max_value = maximum
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result.show_percentage = false
	return result


func _bar_style(color: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(2)
	return style
