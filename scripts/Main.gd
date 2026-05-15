extends Node

const CompanionScene = preload("res://scenes/Companion.tscn")

func _ready() -> void:
	_setup_window()
	var companion := CompanionScene.instantiate()
	add_child(companion)

func _setup_window() -> void:
	get_viewport().transparent_bg = true
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_TRANSPARENT, true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
