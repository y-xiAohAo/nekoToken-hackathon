extends CanvasLayer

signal closed

const INK := Color("#ecf6ff")
const MUTED := Color("#aabed0")
const ACCENT := Color("#81ddee")

var _hint: PanelContainer
var _hint_label: Label
var _shade: ColorRect
var _center: CenterContainer
var _card: VBoxContainer
var _buttons: Array[Button] = []
var _theme: Theme


func _ready() -> void:
	layer = 8
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC", "SimHei"])
	_theme = Theme.new()
	_theme.default_font = font
	_theme.default_font_size = 20
	_theme.set_color("font_color", "Button", INK)
	_theme.set_color("font_hover_color", "Button", Color.WHITE)
	_theme.set_color("font_focus_color", "Button", Color.WHITE)
	_theme.set_stylebox("normal", "Button", _style(Color("#21344a"), Color("#38556b"), 9, 14))
	_theme.set_stylebox("hover", "Button", _style(Color("#29465d"), Color("#71b4cc"), 9, 14))
	_theme.set_stylebox("pressed", "Button", _style(Color("#284f64"), ACCENT, 9, 14))
	_theme.set_stylebox("focus", "Button", _style(Color.TRANSPARENT, ACCENT, 9, 14))

	_hint = PanelContainer.new()
	_hint.theme = _theme
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.add_theme_stylebox_override("panel", _style(Color("#1b293ce8"), Color("#7bb5cf"), 8, 11))
	_hint_label = _label("", 17, INK)
	_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.add_child(_hint_label)
	add_child(_hint)
	_hint.hide()

	_shade = ColorRect.new()
	_shade.color = Color("#0b111cd6")
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_shade)
	_shade.hide()

	_center = CenterContainer.new()
	_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_center.theme = _theme
	add_child(_center)
	_center.hide()

	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 828.0
	panel.add_theme_stylebox_override("panel", _style(Color("#142131"), Color("#39556b"), 18, 26))
	_center.add_child(panel)
	_card = VBoxContainer.new()
	_card.add_theme_constant_override("separation", 16)
	panel.add_child(_card)


func show_hint(target_name: String, projected: Vector2) -> void:
	if target_name.is_empty() or is_open():
		_hint.hide()
		return
	if _hint_label.text != "E  " + target_name:
		_hint_label.text = "E  " + target_name
		_hint.reset_size()
	var viewport_size := get_viewport().get_visible_rect().size
	var desired := projected + Vector2(21.0, -13.0)
	if desired.x + _hint.size.x > viewport_size.x - 10.0:
		desired.x = projected.x - _hint.size.x - 21.0
	_hint.position = desired.clamp(Vector2(10, 60), viewport_size - _hint.size - Vector2(10, 10))
	_hint.show()


func open_prop(data: Dictionary, texture: Texture2D, collected: int, total: int) -> void:
	_begin()
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 26)
	_card.add_child(body)

	var image_frame := PanelContainer.new()
	image_frame.custom_minimum_size = Vector2(238, 238)
	image_frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	image_frame.add_theme_stylebox_override("panel", _style(Color("#1b3045"), Color("#37566b"), 12, 12))
	body.add_child(image_frame)
	var preview := TextureRect.new()
	preview.texture = texture
	preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image_frame.add_child(preview)

	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 14)
	body.add_child(details)
	details.add_child(_label(data.name, 32, INK))
	var description := _label(data.description, 21, INK)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.custom_minimum_size.x = 410.0
	details.add_child(description)
	details.add_child(_label("已收集  ·  %02d / %02d" % [collected, total], 18, ACCENT))
	_add_button("关闭", close)
	_add_keys("Esc 或 E 关闭")


func open_conversation(title: String, line: String, options: Array[String], select: Callable) -> void:
	_begin_message(title, line)
	for index in range(options.size()):
		_add_button(options[index], select.bind(index))
	_add_button("先到这里", close)
	_add_keys("↑ ↓ 选择    Enter 确认    Esc 关闭")


func open_notice(title: String, line: String) -> void:
	_begin_message(title, line)
	_add_button("关闭", close)
	_add_keys("Esc 或 E 关闭")


func is_open() -> bool:
	return _center.visible


func close() -> void:
	if not is_open():
		return
	_center.hide()
	_shade.hide()
	closed.emit()


func choose(number: int) -> void:
	if is_open() and number >= 0 and number < _buttons.size():
		_buttons[number].pressed.emit()


func _begin() -> void:
	_buttons.clear()
	for child in _card.get_children():
		_card.remove_child(child)
		child.queue_free()
	_hint.hide()
	_shade.show()
	_center.show()


func _begin_message(title: String, line: String) -> void:
	_begin()
	_card.add_child(_label(title, 30, ACCENT))
	var message := _label(line, 22, INK)
	message.custom_minimum_size = Vector2(730, 44)
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_card.add_child(message)


func _add_button(text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size.y = 46.0
	button.pressed.connect(action)
	_card.add_child(button)
	_buttons.append(button)
	if _buttons.size() == 1:
		button.grab_focus.call_deferred()


func _add_keys(text: String) -> void:
	var keys := _label(text, 15, MUTED)
	keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_card.add_child(keys)


func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


func _style(fill: Color, edge: Color, radius: int, padding: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = edge
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = padding * 0.6
	style.content_margin_bottom = padding * 0.6
	return style
