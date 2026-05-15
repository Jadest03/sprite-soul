extends Node

const CompanionScene = preload("res://scenes/Companion.tscn")
const AREA_SIZE := Vector2i(300, 200)

func _ready() -> void:
	_setup_window()
	add_child(CompanionScene.instantiate())

func _setup_window() -> void:
	# Usable rect excludes macOS Dock and menu bar
	var usable := DisplayServer.screen_get_usable_rect()
	var pos := usable.position + usable.size - AREA_SIZE
	DisplayServer.window_set_size(AREA_SIZE)
	DisplayServer.window_set_position(pos)

	get_viewport().transparent_bg = true
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_TRANSPARENT, true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
