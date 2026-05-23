extends Node

const PersonaGenerator = preload("res://scripts/PersonaGenerator.gd")
const UserProfile = preload("res://scripts/UserProfile.gd")

signal setup_completed(reference_image_path: String)

# 픽셀 RPG 팔레트
const BG_COLOR      := Color(0.05, 0.05, 0.10)
const PANEL_COLOR   := Color(0.08, 0.08, 0.16)
const INPUT_COLOR   := Color(0.04, 0.04, 0.09)
const BORDER_COLOR  := Color(0.90, 0.75, 0.25)   # 골드
const BORDER_DIM    := Color(0.35, 0.28, 0.08)   # 어두운 골드
const ACCENT_COLOR  := Color(0.90, 0.75, 0.25)
const TEXT_COLOR    := Color(0.95, 0.90, 0.78)   # 따뜻한 흰색
const MUTED_COLOR   := Color(0.50, 0.48, 0.40)
const SELECT_COLOR  := Color(0.20, 0.50, 0.90)   # 파란 선택

const FONT_TITLE   := 36
const FONT_LABEL   := 22
const FONT_INPUT   := 20
const FONT_SUB     := 16
const FONT_BTN     := 20
const FONT_CONFIRM := 24
const BTN_HEIGHT   := 52
const CONFIRM_H    := 86

var _pixel_font: Font

var _name_field: LineEdit
var _appearance_field: LineEdit
var _hf_token_field: LineEdit
var _user_name_field: LineEdit
var _confirm_btn: Button
var _reference_image_path: String = ""
var _ref_preview: TextureRect

func _ready() -> void:
	_pixel_font = load("res://assets/fonts/PixelifySans-Regular.ttf")
	_build_ui()

# ── 스타일 헬퍼 ──────────────────────────────────────────

func _panel_style(bg: Color = PANEL_COLOR, border: Color = BORDER_COLOR, bw: int = 2) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.border_width_left   = bw
	s.border_width_right  = bw
	s.border_width_top    = bw
	s.border_width_bottom = bw
	s.set_content_margin_all(0)
	return s

func _input_style(focused: bool = false) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = INPUT_COLOR
	s.border_color = BORDER_COLOR if focused else BORDER_DIM
	s.border_width_left   = 2
	s.border_width_right  = 2
	s.border_width_top    = 2
	s.border_width_bottom = 2
	s.set_content_margin_all(0)
	return s

func _btn_style(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.border_width_left   = 2
	s.border_width_right  = 2
	s.border_width_top    = 2
	s.border_width_bottom = 2
	s.set_content_margin_all(10)
	return s

func _apply_font(ctrl: Control, size: int) -> void:
	if _pixel_font:
		ctrl.add_theme_font_override("font", _pixel_font)
	ctrl.add_theme_font_size_override("font_size", size)

func _make_label(text: String, size: int, color: Color, wrap: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	_apply_font(l, size)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD
	return l

func _make_separator() -> HSeparator:
	var sep := HSeparator.new()
	var s := StyleBoxFlat.new()
	s.bg_color = BORDER_DIM
	sep.add_theme_stylebox_override("separator", s)
	sep.add_theme_constant_override("separation", 2)
	return sep

func _make_input_field(placeholder: String, size: int, secret: bool = false) -> LineEdit:
	var f := LineEdit.new()
	f.placeholder_text = placeholder
	f.secret = secret
	f.add_theme_color_override("font_color", TEXT_COLOR)
	f.add_theme_color_override("font_placeholder_color", MUTED_COLOR)
	f.add_theme_color_override("caret_color", BORDER_COLOR)
	f.add_theme_color_override("selection_color", SELECT_COLOR)
	f.add_theme_stylebox_override("normal",    _input_style(false))
	f.add_theme_stylebox_override("focus",     _input_style(true))
	f.add_theme_stylebox_override("read_only", _input_style(false))
	_apply_font(f, size)
	return f

func _apply_pixel_btn(btn: Button, bg: Color, border: Color, fg: Color) -> void:
	btn.add_theme_stylebox_override("normal",   _btn_style(bg, border))
	btn.add_theme_stylebox_override("pressed",  _btn_style(bg.darkened(0.2), border))
	btn.add_theme_stylebox_override("hover",    _btn_style(bg.lightened(0.08), border))
	btn.add_theme_stylebox_override("focus",    _btn_style(bg, border))
	btn.add_theme_stylebox_override("disabled", _btn_style(bg.darkened(0.3), BORDER_DIM))
	btn.add_theme_color_override("font_color",         fg)
	btn.add_theme_color_override("font_hover_color",   fg)
	btn.add_theme_color_override("font_pressed_color", fg)
	btn.add_theme_color_override("font_focus_color",   fg)
	_apply_font(btn, FONT_BTN)

# ── UI 빌드 ──────────────────────────────────────────────

func _make_grid_bg() -> Control:
	var tile_size := 12
	var tile_img := Image.create(tile_size, tile_size, false, Image.FORMAT_RGBA8)
	var line_c := Color(0.11, 0.11, 0.22, 1.0)
	for x in tile_size:
		for y in tile_size:
			tile_img.set_pixel(x, y, BG_COLOR)
	for i in tile_size:
		tile_img.set_pixel(0, i, line_c)
		tile_img.set_pixel(i, 0, line_c)
	var tile_tex := ImageTexture.create_from_image(tile_img)
	var bg := TextureRect.new()
	bg.texture = tile_tex
	bg.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	bg.stretch_mode = TextureRect.STRETCH_TILE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return bg

func _build_ui() -> void:
	# 픽셀 그리드 배경
	add_child(_make_grid_bg())

	# 스크롤
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_bottom = -CONFIRM_H
	add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 18)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left",   24)
	margin.add_theme_constant_override("margin_right",  24)
	margin.add_theme_constant_override("margin_top",    24)
	margin.add_theme_constant_override("margin_bottom", 16)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(vbox)
	scroll.add_child(margin)

	_add_title(vbox)
	_add_section(vbox, "▶ 이름", _build_name_content())
	_add_section(vbox, "▶ 외모 설명  (선택)", _build_appearance_content())
	_add_section(vbox, "▶ 캐릭터 이미지", _build_image_content())
	_add_section(vbox, "▶ HuggingFace 토큰", _build_token_content())
	_add_section(vbox, "▶ 내 이름  (선택)", _build_username_content())

	# 하단 확정 버튼
	var footer := PanelContainer.new()
	footer.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	footer.offset_top = -CONFIRM_H
	footer.offset_bottom = 0
	var footer_style := _panel_style(BG_COLOR, BORDER_DIM, 0)
	footer_style.border_width_top = 2
	footer.add_theme_stylebox_override("panel", footer_style)
	add_child(footer)

	var fm := MarginContainer.new()
	fm.add_theme_constant_override("margin_left",   24)
	fm.add_theme_constant_override("margin_right",  24)
	fm.add_theme_constant_override("margin_top",    12)
	fm.add_theme_constant_override("margin_bottom", 12)
	footer.add_child(fm)

	_confirm_btn = Button.new()
	_confirm_btn.text = "▶  완성"
	_confirm_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apply_pixel_btn(_confirm_btn, ACCENT_COLOR.darkened(0.3), ACCENT_COLOR, TEXT_COLOR)
	_apply_font(_confirm_btn, FONT_CONFIRM)
	_confirm_btn.pressed.connect(_on_confirm_pressed)
	fm.add_child(_confirm_btn)

func _add_title(parent: VBoxContainer) -> void:
	var title := _make_label("SPRITE  SOUL", FONT_TITLE, BORDER_COLOR)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(title)
	var sub := _make_label("이름 · 이미지 · 성별만 있으면 돼", FONT_SUB, MUTED_COLOR)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(sub)

func _add_section(parent: VBoxContainer, title: String, content: Control) -> void:
	parent.add_child(_make_separator())
	parent.add_child(_make_label(title, FONT_LABEL, BORDER_COLOR))
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style())
	var inner := MarginContainer.new()
	inner.add_theme_constant_override("margin_left",   12)
	inner.add_theme_constant_override("margin_right",  12)
	inner.add_theme_constant_override("margin_top",    10)
	inner.add_theme_constant_override("margin_bottom", 10)
	inner.add_child(content)
	panel.add_child(inner)
	parent.add_child(panel)

# ── 섹션별 컨텐츠 빌드 ───────────────────────────────────

func _build_name_content() -> Control:
	_name_field = _make_input_field("companion의 이름을 입력해줘", FONT_INPUT)
	return _name_field

func _build_appearance_content() -> Control:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.add_child(_make_label("스프라이트 생성 프롬프트에 반영돼요  (예: girl with pink hair and cat ears)", FONT_SUB, MUTED_COLOR, true))
	_appearance_field = _make_input_field("파란 눈의 소년, 마법사 모자...", FONT_INPUT)
	vbox.add_child(_appearance_field)
	return vbox

func _build_image_content() -> Control:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var pick_btn := Button.new()
	pick_btn.text = "파일 선택"
	pick_btn.custom_minimum_size = Vector2(100, BTN_HEIGHT)
	_apply_pixel_btn(pick_btn, PANEL_COLOR, BORDER_DIM, MUTED_COLOR)

	var path_label := _make_label("선택된 파일 없음", FONT_SUB, MUTED_COLOR)
	path_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	path_label.clip_text = true
	path_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	_ref_preview = TextureRect.new()
	_ref_preview.custom_minimum_size = Vector2(56, 56)
	_ref_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_ref_preview.hide()

	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.filters = ["*.png,*.jpg,*.jpeg,*.webp ; 이미지 파일"]
	add_child(dialog)

	pick_btn.pressed.connect(func(): dialog.popup_centered(Vector2(700, 500)))
	dialog.file_selected.connect(func(path: String):
		_reference_image_path = path
		path_label.text = path.get_file()
		path_label.add_theme_color_override("font_color", TEXT_COLOR)
		_apply_pixel_btn(pick_btn, PANEL_COLOR, BORDER_COLOR, BORDER_COLOR)
		var img := Image.load_from_file(path)
		if img:
			_ref_preview.texture = ImageTexture.create_from_image(img)
			_ref_preview.show()
	)

	row.add_child(pick_btn)
	row.add_child(path_label)
	row.add_child(_ref_preview)
	vbox.add_child(row)

	return vbox

func _build_token_content() -> Control:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.add_child(_make_label("huggingface.co/settings/tokens 에서 발급 (최초 1회)", FONT_SUB, MUTED_COLOR, true))
	_hf_token_field = _make_input_field("hf_...", FONT_INPUT, true)
	var saved := _load_saved_token()
	if not saved.is_empty():
		_hf_token_field.text = saved
	vbox.add_child(_hf_token_field)
	return vbox

func _build_username_content() -> Control:
	_user_name_field = _make_input_field("캐릭터가 나를 부를 이름", FONT_INPUT)
	return _user_name_field

func _load_saved_token() -> String:
	const TOKEN_PATH = "user://hf_token.txt"
	if not FileAccess.file_exists(TOKEN_PATH):
		return OS.get_environment("HF_TOKEN")
	var f := FileAccess.open(TOKEN_PATH, FileAccess.READ)
	if not f:
		return ""
	var token := f.get_as_text().strip_edges()
	f.close()
	return token

# ── 이벤트 ───────────────────────────────────────────────

func _on_confirm_pressed() -> void:
	var name := _name_field.text.strip_edges()
	if name.is_empty():
		_shake(_name_field)
		return
	if _reference_image_path.is_empty():
		_shake(_confirm_btn)
		return
	var hf_token := _hf_token_field.text.strip_edges()
	if hf_token.is_empty():
		_shake(_hf_token_field)
		return
	var tf := FileAccess.open("user://hf_token.txt", FileAccess.WRITE)
	if tf:
		tf.store_string(hf_token)
		tf.close()
	var appearance := _appearance_field.text.strip_edges()
	PersonaGenerator.save_persona(name, {}, appearance)
	var user_name := _user_name_field.text.strip_edges()
	if not user_name.is_empty():
		var profile := UserProfile.new()
		profile.set_name(user_name)
	setup_completed.emit(_reference_image_path)

func _shake(target: Control) -> void:
	var original_x := target.position.x
	var tween := create_tween()
	for i in 3:
		tween.tween_property(target, "position:x", original_x + 6, 0.04)
		tween.tween_property(target, "position:x", original_x - 6, 0.04)
	tween.tween_property(target, "position:x", original_x, 0.04)
