extends Node

const CompanionScene    = preload("res://scenes/Companion.tscn")
const ChatUIScene       = preload("res://scenes/ChatUI.tscn")
const PersonaSetupScene = preload("res://scenes/PersonaSetup.tscn")
const PersonaGenerator  = preload("res://scripts/PersonaGenerator.gd")
const SpriteGenerator   = preload("res://scripts/SpriteGenerator.gd")

const COMPANION_AREA := Vector2i(300, 330)
const SETUP_AREA     := Vector2i(520, 860)

var _generator: Node
var _loading_label: Label
var _progress_bar: ProgressBar

func _ready() -> void:
	if PersonaGenerator.has_saved_persona():
		_setup_companion_window()
		_launch_companion()
	else:
		_setup_setup_window()
		_launch_setup()

# --- Setup mode ---

func _setup_setup_window() -> void:
	get_viewport().transparent_bg = false
	var screen_size := DisplayServer.screen_get_size()
	var pos := screen_size / 2 - SETUP_AREA / 2
	DisplayServer.window_set_size(SETUP_AREA)
	DisplayServer.window_set_position(pos)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_TRANSPARENT, false)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)

func _launch_setup() -> void:
	var setup := PersonaSetupScene.instantiate()
	add_child(setup)
	setup.setup_completed.connect(_on_setup_completed)

func _on_setup_completed(appearance: String, reference_image_path: String) -> void:
	for child in get_children():
		child.queue_free()
	await get_tree().process_frame
	_show_loading_ui()
	_start_sprite_generation(appearance, reference_image_path)

# --- Sprite generation ---

func _show_loading_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.08, 0.12)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(vbox)

	var title := Label.new()
	title.text = "스프라이트 생성 중..."
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(0.92, 0.92, 0.95))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	_loading_label = Label.new()
	_loading_label.text = "모델 로드 중..."
	_loading_label.add_theme_font_size_override("font_size", 19)
	_loading_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
	_loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading_label.custom_minimum_size = Vector2(400, 0)
	vbox.add_child(_loading_label)

	_progress_bar = ProgressBar.new()
	_progress_bar.custom_minimum_size = Vector2(400, 14)
	_progress_bar.max_value = 100
	_progress_bar.value = 0
	_progress_bar.show_percentage = false
	vbox.add_child(_progress_bar)

	var hint := Label.new()
	hint.text = "첫 실행 시 모델 다운로드(~13GB)가 필요해요"
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", Color(0.4, 0.4, 0.45))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hint)

func _start_sprite_generation(appearance: String, reference_image_path: String = "") -> void:
	_generator = SpriteGenerator.new()
	add_child(_generator)
	_generator.progress_updated.connect(_on_gen_progress)
	_generator.generation_completed.connect(_on_gen_completed)
	_generator.generation_failed.connect(_on_gen_failed)
	_generator.generate(appearance, reference_image_path)

func _on_gen_progress(message: String) -> void:
	if message.begins_with("STEP:"):
		var parts := message.split(":", true, 2)
		if parts.size() == 3:
			var current := parts[1].to_int()
			var total   := parts[2].to_int()
			var pct     := int(float(current) / float(total) * 100.0)
			if is_instance_valid(_progress_bar):
				_progress_bar.value = pct
			if is_instance_valid(_loading_label):
				_loading_label.text = "생성 중... %d / %d 스텝 (%d%%)" % [current, total, pct]
	elif message.begins_with("DOWNLOAD:") or message.begins_with("LOAD:"):
		var parts := message.split(":", true, 2)
		if parts.size() == 3:
			var pct     := parts[1].to_int()
			var detail  := parts[2]
			var prefix  := "다운로드 중" if message.begins_with("DOWNLOAD:") else "로드 중"
			if is_instance_valid(_progress_bar):
				_progress_bar.value = pct
			if is_instance_valid(_loading_label):
				_loading_label.text = "모델 %s... %s (%d%%)" % [prefix, detail, pct]
	elif is_instance_valid(_loading_label):
		_loading_label.text = message

func _on_gen_completed() -> void:
	for child in get_children():
		child.queue_free()
	await get_tree().process_frame
	_setup_companion_window()
	_launch_companion()

func _on_gen_failed(error: String) -> void:
	if is_instance_valid(_loading_label):
		_loading_label.text = "오류: " + error
		_loading_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))

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
	companion.reset_requested.connect(_on_reset_requested)
	var chat_ui := ChatUIScene.instantiate()
	add_child(chat_ui)
	chat_ui.companion = companion

func _on_reset_requested() -> void:
	PersonaGenerator.delete_persona()
	_delete_sprites_dir()
	for child in get_children():
		child.queue_free()
	await get_tree().process_frame
	_setup_setup_window()
	_launch_setup()

func _delete_sprites_dir() -> void:
	var dir_path := OS.get_user_data_dir() + "/sprites"
	var dir := DirAccess.open(dir_path)
	if not dir:
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir():
			dir.remove(fname)
		fname = dir.get_next()
	DirAccess.remove_absolute(dir_path)
