extends Node2D

@onready var status_label: Label = $UI/StatusPanel/MarginContainer/StatusLabel


func _ready() -> void:
	var engine_version: String = str(Engine.get_version_info().get("string", "unknown"))
	status_label.text = "2042 FRAMEWORK SHELL\nGodot %s\nWorld / UI ready" % engine_version
	print("FRAMEWORK_SHELL_READY")
