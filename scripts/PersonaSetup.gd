extends Node

const PersonaGenerator = preload("res://scripts/PersonaGenerator.gd")
const UserProfile = preload("res://scripts/UserProfile.gd")

signal setup_completed(appearance: String, reference_image_path: String)

const BG_COLOR     := Color(0.08, 0.08, 0.12)
const TEXT_COLOR   := Color(0.92, 0.92, 0.95)
const MUTED_COLOR  := Color(0.50, 0.50, 0.55)
const ACCENT_COLOR := Color(0.85, 0.55, 0.20)
const BTN_NORMAL   := Color(0.15, 0.15, 0.20)
const BTN_SELECTED := Color(0.85, 0.55, 0.20)

const FONT_TITLE   := 28
const FONT_SUB     := 17
const FONT_LABEL   := 19
const FONT_INPUT   := 18
const FONT_BTN     := 17
const FONT_CONFIRM := 20
const BTN_HEIGHT   := 42
const CONFIRM_H    := 80

var _name_field: LineEdit
var _hf_token_field: LineEdit
var _user_name_field: LineEdit
var _confirm_btn: Button
var _reference_image_path: String = ""
var _ref_preview: TextureRect
var _char_hints_field: LineEdit

var _style_normal: StyleBoxFlat
var _style_selected: StyleBoxFlat

func _ready() -> void:
	_init_styles()
	_build_ui()

func _init_styles() -> void:
	_style_normal = _make_flat_style(BTN_NORMAL, 6)
	_style_selected = _make_flat_style(BTN_SELECTED, 6)

func _make_flat_style(bg: Color, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.corner_radius_top_left     = radius
	s.corner_radius_top_right    = radius
	s.corner_radius_bottom_left  = radius
	s.corner_radius_bottom_right = radius
	s.set_content_margin_all(10)
	return s

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_bottom = -CONFIRM_H
	add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 22)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left",   28)
	margin.add_theme_constant_override("margin_right",  28)
	margin.add_theme_constant_override("margin_top",    28)
	margin.add_theme_constant_override("margin_bottom", 20)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(vbox)
	scroll.add_child(margin)

	_add_title(vbox)
	_add_name_section(vbox)
	_add_reference_image_section(vbox)
	_add_hf_token_section(vbox)
	_add_user_name_section(vbox)

	# 하단 고정 완성 버튼
	var btn_container := PanelContainer.new()
	btn_container.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	btn_container.offset_top = -CONFIRM_H
	btn_container.offset_bottom = 0
	var btn_style := StyleBoxFlat.new()
	btn_style.bg_color = BG_COLOR
	btn_style.border_color = Color(0.2, 0.2, 0.25)
	btn_style.border_width_top = 1
	btn_style.set_content_margin_all(0)
	btn_container.add_theme_stylebox_override("panel", btn_style)
	add_child(btn_container)

	var btn_margin := MarginContainer.new()
	btn_margin.add_theme_constant_override("margin_left",   28)
	btn_margin.add_theme_constant_override("margin_right",  28)
	btn_margin.add_theme_constant_override("margin_top",    14)
	btn_margin.add_theme_constant_override("margin_bottom", 14)
	btn_container.add_child(btn_margin)

	_confirm_btn = Button.new()
	_confirm_btn.text = "완성"
	_confirm_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_confirm_btn.add_theme_font_size_override("font_size", FONT_CONFIRM)
	_apply_btn_style(_confirm_btn, ACCENT_COLOR, Color(1, 1, 1))
	_confirm_btn.pressed.connect(_on_confirm_pressed)
	btn_margin.add_child(_confirm_btn)

func _add_reference_image_section(parent: VBoxContainer) -> void:
	var sep := HSeparator.new()
	sep.add_theme_color_override("color", Color(0.2, 0.2, 0.25))
	parent.add_child(sep)

	var label := Label.new()
	label.text = "캐릭터 참고 이미지 (선택)"
	label.add_theme_font_size_override("font_size", FONT_LABEL)
	label.add_theme_color_override("font_color", TEXT_COLOR)
	parent.add_child(label)

	var hint := Label.new()
	hint.text = "이미지를 넣으면 해당 캐릭터를 픽셀아트로 변환해요. 없으면 텍스트 설명으로 생성."
	hint.add_theme_font_size_override("font_size", FONT_SUB)
	hint.add_theme_color_override("font_color", MUTED_COLOR)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	parent.add_child(hint)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)

	var pick_btn := Button.new()
	pick_btn.text = "이미지 선택"
	pick_btn.add_theme_font_size_override("font_size", FONT_BTN)
	pick_btn.custom_minimum_size = Vector2(120, BTN_HEIGHT)
	_apply_btn_style(pick_btn, BTN_NORMAL, MUTED_COLOR)

	var path_label := Label.new()
	path_label.text = "선택된 파일 없음"
	path_label.add_theme_font_size_override("font_size", FONT_BTN)
	path_label.add_theme_color_override("font_color", MUTED_COLOR)
	path_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	path_label.clip_text = true

	_ref_preview = TextureRect.new()
	_ref_preview.custom_minimum_size = Vector2(64, 64)
	_ref_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_ref_preview.hide()

	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.filters = ["*.png,*.jpg,*.jpeg,*.webp ; 이미지 파일"]
	add_child(dialog)

	pick_btn.pressed.connect(func():
		dialog.popup_centered(Vector2(700, 500))
	)
	dialog.file_selected.connect(func(path: String):
		_reference_image_path = path
		path_label.text = path.get_file()
		path_label.add_theme_color_override("font_color", TEXT_COLOR)
		_apply_btn_style(pick_btn, BTN_SELECTED, Color(1, 1, 1))
		var img := Image.load_from_file(path)
		if img:
			_ref_preview.texture = ImageTexture.create_from_image(img)
			_ref_preview.show()
	)

	row.add_child(pick_btn)
	row.add_child(path_label)
	row.add_child(_ref_preview)

	# 선택적 특징 힌트 필드
	var hints_label := Label.new()
	hints_label.text = "특징 힌트 (선택) — 이미지로 잡기 어려운 디테일을 영어로 적어주세요"
	hints_label.add_theme_font_size_override("font_size", FONT_SUB)
	hints_label.add_theme_color_override("font_color", MUTED_COLOR)
	parent.add_child(hints_label)

	var hints_panel := PanelContainer.new()
	var hints_style := StyleBoxFlat.new()
	hints_style.bg_color = BTN_NORMAL
	hints_style.corner_radius_top_left     = 8
	hints_style.corner_radius_top_right    = 8
	hints_style.corner_radius_bottom_left  = 8
	hints_style.corner_radius_bottom_right = 8
	hints_panel.add_theme_stylebox_override("panel", hints_style)
	parent.add_child(hints_panel)

	var hints_margin := MarginContainer.new()
	hints_margin.add_theme_constant_override("margin_left",  10)
	hints_margin.add_theme_constant_override("margin_right", 10)
	hints_margin.add_theme_constant_override("margin_top",    6)
	hints_margin.add_theme_constant_override("margin_bottom", 6)
	hints_panel.add_child(hints_margin)

	_char_hints_field = LineEdit.new()
	_char_hints_field.placeholder_text = "예: white spiky hair, black blindfold, dark suit"
	_char_hints_field.add_theme_font_size_override("font_size", FONT_BTN)
	_char_hints_field.add_theme_color_override("font_color", TEXT_COLOR)
	_char_hints_field.add_theme_color_override("font_placeholder_color", MUTED_COLOR)
	var empty := StyleBoxEmpty.new()
	_char_hints_field.add_theme_stylebox_override("normal", empty)
	_char_hints_field.add_theme_stylebox_override("focus",  empty)
	hints_margin.add_child(_char_hints_field)

func _add_title(parent: VBoxContainer) -> void:
	var title := Label.new()
	title.text = "새로운 companion 만들기"
	title.add_theme_font_size_override("font_size", FONT_TITLE)
	title.add_theme_color_override("font_color", TEXT_COLOR)
	parent.add_child(title)

	var sub := Label.new()
	sub.text = "이미지와 이름만 있으면 돼"
	sub.add_theme_font_size_override("font_size", FONT_SUB)
	sub.add_theme_color_override("font_color", MUTED_COLOR)
	parent.add_child(sub)

func _add_name_section(parent: VBoxContainer) -> void:
	var sep := HSeparator.new()
	sep.add_theme_color_override("color", Color(0.2, 0.2, 0.25))
	parent.add_child(sep)

	var label := Label.new()
	label.text = "이름"
	label.add_theme_font_size_override("font_size", FONT_LABEL)
	label.add_theme_color_override("font_color", TEXT_COLOR)
	parent.add_child(label)

	var panel := PanelContainer.new()
	var ps := StyleBoxFlat.new()
	ps.bg_color = BTN_NORMAL
	ps.corner_radius_top_left     = 8
	ps.corner_radius_top_right    = 8
	ps.corner_radius_bottom_left  = 8
	ps.corner_radius_bottom_right = 8
	ps.set_content_margin_all(0)
	panel.add_theme_stylebox_override("panel", ps)
	parent.add_child(panel)

	var pm := MarginContainer.new()
	pm.add_theme_constant_override("margin_left",   12)
	pm.add_theme_constant_override("margin_right",  12)
	pm.add_theme_constant_override("margin_top",     8)
	pm.add_theme_constant_override("margin_bottom",  8)
	panel.add_child(pm)

	_name_field = LineEdit.new()
	_name_field.placeholder_text = "companion의 이름을 입력해줘"
	_name_field.add_theme_font_size_override("font_size", FONT_INPUT)
	_name_field.add_theme_color_override("font_color", TEXT_COLOR)
	_name_field.add_theme_color_override("font_placeholder_color", MUTED_COLOR)
	var empty := StyleBoxEmpty.new()
	_name_field.add_theme_stylebox_override("normal",    empty)
	_name_field.add_theme_stylebox_override("focus",     empty)
	_name_field.add_theme_stylebox_override("read_only", empty)
	pm.add_child(_name_field)

func _apply_btn_style(btn: Button, bg: Color, fg: Color) -> void:
	var is_selected := bg == BTN_SELECTED
	var base := _style_selected if is_selected else _style_normal
	for state in ["normal", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(state, base)
	var hover := _make_flat_style(bg.lightened(0.05), 6)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_color_override("font_color",         fg)
	btn.add_theme_color_override("font_hover_color",   fg)
	btn.add_theme_color_override("font_pressed_color", fg)
	btn.add_theme_color_override("font_focus_color",   fg)

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
	var appearance := _char_hints_field.text.strip_edges() if _char_hints_field else ""
	PersonaGenerator.save_persona(name, {}, appearance)
	var user_name := _user_name_field.text.strip_edges()
	if not user_name.is_empty():
		var profile := UserProfile.new()
		profile.set_name(user_name)
	setup_completed.emit(appearance, _reference_image_path)

func _shake(target: Control) -> void:
	var original_x := target.position.x
	var tween := create_tween()
	for i in 3:
		tween.tween_property(target, "position:x", original_x + 8, 0.05)
		tween.tween_property(target, "position:x", original_x - 8, 0.05)
	tween.tween_property(target, "position:x", original_x, 0.05)
