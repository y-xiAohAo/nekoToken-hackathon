extends Control

const FIRST_DISTRICT := "res://world2.tscn"
const PAGES := [
	[
		{
			"lines": [
				"公元2046年。",
				"人类曾创造机器，以解放自己的双手；",
				"后来创造人工智能，以延伸自己的智慧。",
				"直到通用人工智能（AGI）的诞生，",
				"人类第一次发现，自己不再是这个世界上唯一能够创造未来的智慧。",
				"有人将它的降临视为神启，自称「艾吉尔」，甘愿将自己的生活乃至命运托付于它。",
				"有人拒绝接受这样的未来，以「旧日之子」为名，捍卫人类决定自身命运的权利。",
				"有人走向繁荣的智能都市，有人退守城市角落的「蚁穴」。",
				"他们都坚信，自己正在守护人类的未来。",
				"只是，从那一天起，",
			],
			"emphasis": {0: 32},
		},
		{
			"lines": ["人类便不再拥有同一个明天。"],
			"emphasis": {0: 47},
		},
	],
	[
		{
			"lines": [
				"今天，是索菲亚失踪的第",
				"2 天",
				"也是爸爸妈妈失踪的第",
				"1325 天",
			],
			"emphasis": {1: 64, 3: 64},
		},
		{
			"lines": [
				"贾斯珀叔叔还是和以前一样，什么都不肯告诉我。",
				"他总说，等我再长大一点，就会明白的。",
				"可我已经等了很久，很久。",
				"这一次，我不想再等了。",
				"听说，在归岸镇以北五公里的地方，有一座叫作「明日镇」的城市。",
				"那是爸爸妈妈倾注了无数心血建造的地方，也是这个时代最引以为傲的奇迹。",
				"或许，那里会有我一直在寻找的答案。",
			],
			"emphasis": {3: 30},
		},
		{
			"lines": ["索菲亚，等我。", "哥哥来接你回家。"],
			"emphasis": {0: 32, 1: 47},
		},
	],
]
const PLAYBACK_TIME_MULTIPLIER := 2.0
const OPENING_DELAY := 0.43 * PLAYBACK_TIME_MULTIPLIER
const CHARACTER_INTERVAL := 0.045 * PLAYBACK_TIME_MULTIPLIER
const EMPHASIS_INTERVAL := 0.8 * PLAYBACK_TIME_MULTIPLIER
const TEXT_FADE_OUT := 0.30 * PLAYBACK_TIME_MULTIPLIER
const DISTRICT_FADE_IN := 1.35 * PLAYBACK_TIME_MULTIPLIER

enum Phase { REVEAL, FADE_OUT, FINISHED }

var _page := 0
var _part := 0
var _phase := Phase.REVEAL
var _leaving := false
var _sequence: Tween
var _labels: Array[Label] = []

@onready var _story: VBoxContainer = $Story
@onready var _actions: CenterContainer = $Actions
@onready var _enter_button: Button = $Actions/EnterGuian


func _ready() -> void:
	_enter_button.pressed.connect(_begin_play)
	_show_part()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		_enter_game()
	elif event.is_action_pressed(&"ui_accept") or event.is_action_pressed(&"interact"):
		get_viewport().set_input_as_handled()
		if _phase == Phase.FINISHED:
			_begin_play()
		elif _phase == Phase.REVEAL:
			_show_passage()


func _current_part() -> Dictionary:
	return PAGES[_page][_part]


func _show_part() -> void:
	for label in _labels:
		_story.remove_child(label)
		label.queue_free()
	_labels.clear()
	_story.modulate.a = 1.0
	var part := _current_part()
	var emphasis: Dictionary = part.get("emphasis", {})
	_phase = Phase.REVEAL
	_sequence = create_tween()
	if _page == 0 and _part == 0:
		_sequence.tween_interval(OPENING_DELAY)
	var last_line: int = part.lines.size() - 1
	for index in range(part.lines.size()):
		var label := Label.new()
		label.text = part.lines[index]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override("font_size", emphasis.get(index, 25))
		label.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
		label.visible_characters = 0
		_story.add_child(label)
		_labels.append(label)
		if emphasis.has(index):
			_sequence.tween_callback(label.set_visible_characters.bind(label.text.length()))
			var transition := TEXT_FADE_OUT if index == last_line and not _is_final_part() else 0.0
			_sequence.tween_interval(EMPHASIS_INTERVAL - transition)
		else:
			_sequence.tween_property(label, "visible_characters", label.text.length(),
				label.text.length() * CHARACTER_INTERVAL)
	_sequence.tween_callback(_finish_part)


func _show_passage() -> void:
	_sequence.kill()
	for label in _labels:
		label.visible_characters = label.text.length()
	_sequence = create_tween()
	var transition := 0.0 if _is_final_part() else TEXT_FADE_OUT
	_sequence.tween_interval(EMPHASIS_INTERVAL - transition)
	_sequence.tween_callback(_finish_part)


func _finish_part() -> void:
	if _is_final_part():
		_phase = Phase.FINISHED
		_actions.show()
	else:
		_fade_out()


func _begin_play() -> void:
	if _phase == Phase.FINISHED:
		_actions.hide()
		_fade_out()


func _fade_out() -> void:
	_phase = Phase.FADE_OUT
	_sequence = create_tween()
	_sequence.tween_property(_story, "modulate:a", 0.0, TEXT_FADE_OUT).set_trans(Tween.TRANS_SINE)
	_sequence.tween_callback(_advance)


func _is_final_part() -> bool:
	return _page == PAGES.size() - 1 and _part == PAGES[_page].size() - 1


func _advance() -> void:
	if _is_final_part():
		_enter_game()
		return
	_part += 1
	if _part == PAGES[_page].size():
		_page += 1
		_part = 0
	_show_part()


func _enter_game() -> void:
	if _leaving:
		return
	_leaving = true
	if _sequence and _sequence.is_valid():
		_sequence.kill()
	var tree := get_tree()
	var reveal := DistrictReveal.new()
	reveal.name = "OpeningReveal"
	tree.root.add_child(reveal)
	tree.scene_changed.connect(reveal.fade_in.bind(DISTRICT_FADE_IN), CONNECT_ONE_SHOT)
	var error := tree.change_scene_to_file(FIRST_DISTRICT)
	if error != OK:
		reveal.queue_free()
		_leaving = false
		push_error("无法进入归岸镇：%s" % error_string(error))


class DistrictReveal extends CanvasLayer:
	var _black := ColorRect.new()

	func _ready() -> void:
		layer = 100
		_black.color = Color.BLACK
		_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_black)
		_black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	func fade_in(duration: float) -> void:
		var tween := create_tween()
		tween.tween_property(_black, "color:a", 0.0, duration).set_trans(Tween.TRANS_SINE)
		tween.tween_callback(queue_free)
