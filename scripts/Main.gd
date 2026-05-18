extends Node

const CompanionScene    = preload("res://scenes/Companion.tscn")
const ChatUIScene       = preload("res://scenes/ChatUI.tscn")
const PersonaSetupScene = preload("res://scenes/PersonaSetup.tscn")
const PersonaGenerator  = preload("res://scripts/PersonaGenerator.gd")
const SpriteGenerator   = preload("res://scripts/SpriteGenerator.gd")

const COMPANION_AREA := Vector2i(300, 330)
const SETUP_AREA     := Vector2i(820, 1100)

const BG_COLOR     := Color(0.05, 0.05, 0.10)
const PANEL_COLOR  := Color(0.08, 0.08, 0.16)
const BORDER_COLOR := Color(0.90, 0.75, 0.25)
const BORDER_DIM   := Color(0.35, 0.28, 0.08)
const ACCENT_COLOR := Color(0.90, 0.75, 0.25)
const TEXT_COLOR   := Color(0.95, 0.90, 0.78)
const MUTED_COLOR  := Color(0.50, 0.48, 0.40)

var _generator: Node
var _loading_label: Label
var _progress_bar: ProgressBar

var _gen_reference_image_path: String = ""

# 프리뷰
var _preview_rect: TextureRect
var _preview_timer: Timer
var _preview_anim: String = "idle"
var _preview_frame: int = 0
var _preview_textures: Dictionary = {}
var _anim_btns: Dictionary = {}

var _pixel_font: Font

func _ready() -> void:
	_pixel_font = load("res://assets/fonts/PixelifySans-Regular.ttf")
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
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, false)

func _launch_setup() -> void:
	var setup := PersonaSetupScene.instantiate()
	add_child(setup)
	setup.setup_completed.connect(_on_setup_completed)

func _on_setup_completed(reference_image_path: String) -> void:
	_gen_reference_image_path = reference_image_path
	for child in get_children():
		child.queue_free()
	await get_tree().process_frame
	_show_loading_ui()
	_start_sprite_generation()

# --- Sprite generation ---

func _show_loading_ui() -> void:
	var bg := ColorRect.new()
	bg.color = BG_COLOR
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
	title.add_theme_color_override("font_color", TEXT_COLOR)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if _pixel_font: title.add_theme_font_override("font", _pixel_font)
	vbox.add_child(title)

	_loading_label = Label.new()
	_loading_label.text = "모델 로드 중..."
	_loading_label.add_theme_font_size_override("font_size", 19)
	_loading_label.add_theme_color_override("font_color", MUTED_COLOR)
	_loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading_label.custom_minimum_size = Vector2(400, 0)
	if _pixel_font: _loading_label.add_theme_font_override("font", _pixel_font)
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
	hint.add_theme_color_override("font_color", MUTED_COLOR.darkened(0.2))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if _pixel_font: hint.add_theme_font_override("font", _pixel_font)
	vbox.add_child(hint)

func _start_sprite_generation() -> void:
	_generator = SpriteGenerator.new()
	add_child(_generator)
	_generator.progress_updated.connect(_on_gen_progress)
	_generator.generation_completed.connect(_on_gen_completed)
	_generator.generation_failed.connect(_on_gen_failed)
	_generator.generate(_gen_reference_image_path, 42)

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
			var pct    := parts[1].to_int()
			var detail := parts[2]
			var prefix := "다운로드 중" if message.begins_with("DOWNLOAD:") else "로드 중"
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
	_show_preview()

func _on_gen_failed(error: String) -> void:
	if is_instance_valid(_loading_label):
		_loading_label.text = "오류: " + error
		_loading_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))

# --- Preview ---

func _show_preview() -> void:
	var sprites_dir := OS.get_user_data_dir() + "/sprites/"
	_preview_textures = {
		"idle":  [_load_tex(sprites_dir + "idle_1.png")],
		"walk":  [_load_tex(sprites_dir + "walk_1.png"),
		          _load_tex(sprites_dir + "walk_2.png"),
		          _load_tex(sprites_dir + "walk_3.png")],
		"sleep": [_load_tex(sprites_dir + "sleep_1.png")],
	}
	_preview_anim = "idle"
	_preview_frame = 0
	_anim_btns = {}

	# 배경
	var bg := ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# 전체 레이아웃
	var root := MarginContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("margin_left",   32)
	root.add_theme_constant_override("margin_right",  32)
	root.add_theme_constant_override("margin_top",    40)
	root.add_theme_constant_override("margin_bottom", 32)
	add_child(root)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 24)
	root.add_child(vbox)

	# 타이틀
	var title := Label.new()
	title.text = "생성 완료!"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", BORDER_COLOR)
	title.add_theme_font_size_override("font_size", 36)
	if _pixel_font: title.add_theme_font_override("font", _pixel_font)
	vbox.add_child(title)

	# 스프라이트 프리뷰 영역
	var sprite_panel := PanelContainer.new()
	sprite_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = PANEL_COLOR
	panel_style.border_color = BORDER_COLOR
	panel_style.border_width_left   = 2
	panel_style.border_width_right  = 2
	panel_style.border_width_top    = 2
	panel_style.border_width_bottom = 2
	panel_style.set_content_margin_all(0)
	sprite_panel.add_theme_stylebox_override("panel", panel_style)
	vbox.add_child(sprite_panel)

	var sprite_center := CenterContainer.new()
	sprite_panel.add_child(sprite_center)

	_preview_rect = TextureRect.new()
	_preview_rect.custom_minimum_size = Vector2(384, 384)
	_preview_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_preview_rect.texture = _preview_textures["idle"][0]
	sprite_center.add_child(_preview_rect)

	# 애니메이션 선택 버튼
	var anim_row := HBoxContainer.new()
	anim_row.add_theme_constant_override("separation", 12)
	anim_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(anim_row)

	for entry in [["idle", "대기"], ["walk", "걷기"], ["sleep", "수면"]]:
		var key: String   = entry[0]
		var label: String = entry[1]
		var btn := Button.new()
		btn.text = label
		btn.custom_minimum_size = Vector2(160, 52)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if _pixel_font: btn.add_theme_font_override("font", _pixel_font)
		btn.add_theme_font_size_override("font_size", 20)
		_anim_btns[key] = btn
		btn.pressed.connect(func(): _set_preview_anim(key))
		anim_row.add_child(btn)
	_refresh_anim_btn_styles()

	# 구분선
	var sep := HSeparator.new()
	var sep_style := StyleBoxFlat.new()
	sep_style.bg_color = BORDER_DIM
	sep.add_theme_stylebox_override("separator", sep_style)
	sep.add_theme_constant_override("separation", 2)
	vbox.add_child(sep)

	# 이대로 시작 버튼
	var confirm_btn := Button.new()
	confirm_btn.text = "▶  이대로 시작"
	confirm_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	confirm_btn.custom_minimum_size = Vector2(0, 72)
	if _pixel_font: confirm_btn.add_theme_font_override("font", _pixel_font)
	confirm_btn.add_theme_font_size_override("font_size", 22)
	_apply_btn(confirm_btn, ACCENT_COLOR.darkened(0.3), ACCENT_COLOR, TEXT_COLOR)
	confirm_btn.pressed.connect(_on_preview_confirmed)
	vbox.add_child(confirm_btn)

	# 애니메이션 타이머
	_preview_timer = Timer.new()
	_preview_timer.wait_time = 1.0 / 6.0
	_preview_timer.timeout.connect(_on_preview_tick)
	add_child(_preview_timer)
	_preview_timer.start()

func _load_tex(path: String) -> ImageTexture:
	var img := Image.load_from_file(path)
	return ImageTexture.create_from_image(img) if img else null

func _set_preview_anim(anim: String) -> void:
	_preview_anim = anim
	_preview_frame = 0
	var frames: Array = _preview_textures[anim]
	if frames[0]:
		_preview_rect.texture = frames[0]
	_refresh_anim_btn_styles()

func _refresh_anim_btn_styles() -> void:
	for key in _anim_btns:
		var btn: Button = _anim_btns[key]
		if key == _preview_anim:
			_apply_btn(btn, ACCENT_COLOR.darkened(0.2), ACCENT_COLOR, TEXT_COLOR)
		else:
			_apply_btn(btn, PANEL_COLOR, BORDER_DIM, MUTED_COLOR)

func _on_preview_tick() -> void:
	var frames: Array = _preview_textures[_preview_anim]
	if frames.size() <= 1:
		return
	_preview_frame = (_preview_frame + 1) % frames.size()
	if frames[_preview_frame]:
		_preview_rect.texture = frames[_preview_frame]

func _on_preview_confirmed() -> void:
	if _preview_timer and is_instance_valid(_preview_timer):
		_preview_timer.stop()
	for child in get_children():
		child.queue_free()
	await get_tree().process_frame
	_setup_companion_window()
	_launch_companion()

func _apply_btn(btn: Button, bg: Color, border: Color, fg: Color) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.border_width_left   = 2
	s.border_width_right  = 2
	s.border_width_top    = 2
	s.border_width_bottom = 2
	s.set_content_margin_all(10)
	btn.add_theme_stylebox_override("normal",   s)
	var sh := s.duplicate(); sh.bg_color = bg.lightened(0.08)
	btn.add_theme_stylebox_override("hover",    sh)
	var sp := s.duplicate(); sp.bg_color = bg.darkened(0.2)
	btn.add_theme_stylebox_override("pressed",  sp)
	btn.add_theme_stylebox_override("focus",    s)
	btn.add_theme_color_override("font_color",         fg)
	btn.add_theme_color_override("font_hover_color",   fg)
	btn.add_theme_color_override("font_pressed_color", fg)

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
	for fname: String in ["user_profile.json", "memory.json"]:
		var path: String = "user://" + fname
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
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
