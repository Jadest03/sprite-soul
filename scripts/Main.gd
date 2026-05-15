extends Node

const CompanionScene   = preload("res://scenes/Companion.tscn")
const ChatUIScene      = preload("res://scenes/ChatUI.tscn")
const PersonaSetupScene = preload("res://scenes/PersonaSetup.tscn")
const PersonaGenerator = preload("res://scripts/PersonaGenerator.gd")

const COMPANION_AREA := Vector2i(300, 200)
const SETUP_AREA     := Vector2i(520, 860)

func _ready() -> void:
	if PersonaGenerator.has_saved_persona():
		_setup_companion_window()
		_launch_companion()
	else:
		_setup_setup_window()
		_launch_setup()

# --- Setup mode ---

func _setup_setup_window() -> void:
	var screen_size := DisplayServer.screen_get_size()
	var pos := screen_size / 2 - SETUP_AREA / 2
	DisplayServer.window_set_size(SETUP_AREA)
	DisplayServer.window_set_position(pos)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_TRANSPARENT, false)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, false)

func _launch_setup() -> void:
	var setup := PersonaSetupScene.instantiate()
	add_child(setup)
	setup.setup_completed.connect(_on_setup_completed)

func _on_setup_completed() -> void:
	for child in get_children():
		child.queue_free()
	_setup_companion_window()
	# queue_free가 끝난 다음 프레임에 companion 시작
	await get_tree().process_frame
	_launch_companion()

# --- Companion mode ---

func _setup_companion_window() -> void:
	var usable := DisplayServer.screen_get_usable_rect()
	var pos := usable.position + usable.size - COMPANION_AREA
	DisplayServer.window_set_size(COMPANION_AREA)
	DisplayServer.window_set_position(pos)
	get_viewport().transparent_bg = true
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_TRANSPARENT, true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)

func _launch_companion() -> void:
	var companion := CompanionScene.instantiate()
	add_child(companion)
	var chat_ui := ChatUIScene.instantiate()
	add_child(chat_ui)
	chat_ui.companion = companion
