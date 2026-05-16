extends Node

const PersonaData = preload("res://scripts/PersonaData.gd")
const PersonaGenerator = preload("res://scripts/PersonaGenerator.gd")
const UserProfile = preload("res://scripts/UserProfile.gd")

signal setup_completed(appearance: String)

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
var _selections: Dictionary = {}
var _confirm_btn: Button
var _appearance_fields: Dictionary = {}
var _appearance_field_nodes: Dictionary = {}
var _gender_group: ButtonGroup

# 버튼 스타일 캐시 — 토글 시마다 재생성하지 않도록
var _style_normal: StyleBoxFlat
var _style_selected: StyleBoxFlat

const REQUIRED_APPEARANCE := ["gender", "skin", "hair_color", "hair_length", "hair_style", "eye_color", "top", "bottom"]

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
	_add_appearance_section(vbox)
	_add_hf_token_section(vbox)
	_add_user_name_section(vbox)
	for category in PersonaData.CATEGORIES:
		_add_category_section(vbox, category)

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

func _add_title(parent: VBoxContainer) -> void:
	var title := Label.new()
	title.text = "새로운 companion 만들기"
	title.add_theme_font_size_override("font_size", FONT_TITLE)
	title.add_theme_color_override("font_color", TEXT_COLOR)
	parent.add_child(title)

	var sub := Label.new()
	sub.text = "각 항목에서 하나씩 선택해줘"
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

func _add_appearance_section(parent: VBoxContainer) -> void:
	var sep := HSeparator.new()
	sep.add_theme_color_override("color", Color(0.2, 0.2, 0.25))
	parent.add_child(sep)

	var label := Label.new()
	label.text = "외모"
	label.add_theme_font_size_override("font_size", FONT_LABEL)
	label.add_theme_color_override("font_color", TEXT_COLOR)
	parent.add_child(label)

	var hint := Label.new()
	hint.text = "입력한 정보로 스프라이트를 자동 생성해요  (* 필수)"
	hint.add_theme_font_size_override("font_size", FONT_SUB)
	hint.add_theme_color_override("font_color", MUTED_COLOR)
	parent.add_child(hint)

	# Gender buttons
	var gender_lbl := Label.new()
	gender_lbl.text = "성별 *"
	gender_lbl.add_theme_font_size_override("font_size", FONT_BTN)
	gender_lbl.add_theme_color_override("font_color", MUTED_COLOR)
	parent.add_child(gender_lbl)

	var gender_row := HBoxContainer.new()
	gender_row.add_theme_constant_override("separation", 8)
	parent.add_child(gender_row)

	_gender_group = ButtonGroup.new()
	for pair in [["여자", "female"], ["남자", "male"]]:
		var btn := Button.new()
		btn.text = pair[0]
		btn.toggle_mode = true
		btn.button_group = _gender_group
		btn.add_theme_font_size_override("font_size", FONT_BTN)
		btn.custom_minimum_size = Vector2(88, BTN_HEIGHT)
		_apply_btn_style(btn, BTN_NORMAL, MUTED_COLOR)
		var val: String = pair[1]
		btn.toggled.connect(func(on: bool):
			if on:
				_apply_btn_style(btn, BTN_SELECTED, Color(1, 1, 1))
				_appearance_fields["gender"] = val
			else:
				_apply_btn_style(btn, BTN_NORMAL, MUTED_COLOR)
		)
		gender_row.add_child(btn)

	# Required fields
	_add_appearance_field(parent, "피부색 *",     "skin",        "fair / light / medium / tan / dark")
	_add_appearance_field(parent, "머리 색 *",    "hair_color",  "black / blonde / brown / red / white / pink")
	_add_appearance_field(parent, "머리 길이 *",  "hair_length", "short / medium / long")
	_add_appearance_field(parent, "머리 스타일 *","hair_style",  "straight / curly / ponytail / twin tails / braided")
	_add_appearance_field(parent, "눈 색 *",      "eye_color",   "brown / blue / green / red / purple / black")
	_add_appearance_field(parent, "상의 *",       "top",         "white shirt / blue hoodie / black jacket")
	_add_appearance_field(parent, "하의 *",       "bottom",      "jeans / skirt / shorts / dress")

	# Optional fields
	_add_appearance_field(parent, "신발",   "shoes",     "sneakers / boots / sandals")
	_add_appearance_field(parent, "모자",   "hat",       "baseball cap / beanie / bow")
	_add_appearance_field(parent, "악세서리","accessory", "glasses / scarf / bag")
	_add_appearance_field(parent, "분위기", "vibe",      "cute / cool / casual / sporty / elegant")

func _add_appearance_field(parent: VBoxContainer, label_text: String, key: String, placeholder: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(row)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", FONT_BTN)
	lbl.add_theme_color_override("font_color", MUTED_COLOR)
	lbl.custom_minimum_size = Vector2(96, 0)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(lbl)

	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var ps := StyleBoxFlat.new()
	ps.bg_color = BTN_NORMAL
	ps.corner_radius_top_left     = 6
	ps.corner_radius_top_right    = 6
	ps.corner_radius_bottom_left  = 6
	ps.corner_radius_bottom_right = 6
	ps.set_content_margin_all(0)
	panel.add_theme_stylebox_override("panel", ps)
	row.add_child(panel)

	var pm := MarginContainer.new()
	pm.add_theme_constant_override("margin_left",  10)
	pm.add_theme_constant_override("margin_right", 10)
	pm.add_theme_constant_override("margin_top",    6)
	pm.add_theme_constant_override("margin_bottom", 6)
	panel.add_child(pm)

	var field := LineEdit.new()
	field.placeholder_text = placeholder
	field.add_theme_font_size_override("font_size", FONT_BTN)
	field.add_theme_color_override("font_color", TEXT_COLOR)
	field.add_theme_color_override("font_placeholder_color", MUTED_COLOR)
	var empty := StyleBoxEmpty.new()
	field.add_theme_stylebox_override("normal",    empty)
	field.add_theme_stylebox_override("focus",     empty)
	field.add_theme_stylebox_override("read_only", empty)
	field.text_changed.connect(func(text: String):
		var trimmed := text.strip_edges()
		if trimmed.is_empty():
			_appearance_fields.erase(key)
		else:
			_appearance_fields[key] = trimmed
	)
	pm.add_child(field)
	_appearance_field_nodes[key] = field

func _build_appearance_string() -> String:
	var gender: String = _appearance_fields.get("gender", "female")
	var skin: String = _appearance_fields.get("skin", "")
	var hair_color: String = _appearance_fields.get("hair_color", "")
	var hair_length: String = _appearance_fields.get("hair_length", "")
	var hair_style: String = _appearance_fields.get("hair_style", "")
	var eye_color: String = _appearance_fields.get("eye_color", "")
	var top: String = _appearance_fields.get("top", "")
	var bottom: String = _appearance_fields.get("bottom", "")
	var shoes: String = _appearance_fields.get("shoes", "")
	var hat: String = _appearance_fields.get("hat", "")
	var accessory: String = _appearance_fields.get("accessory", "")
	var vibe: String = _appearance_fields.get("vibe", "")

	var parts: Array[String] = []
	parts.append(gender)
	if not skin.is_empty():
		parts.append("with %s skin" % skin)

	var hair_parts: Array[String] = []
	if not hair_color.is_empty(): hair_parts.append(hair_color)
	if not hair_length.is_empty(): hair_parts.append(hair_length)
	if not hair_style.is_empty(): hair_parts.append(hair_style)
	if not hair_parts.is_empty():
		parts.append("%s hair" % " ".join(hair_parts))

	if not eye_color.is_empty():
		parts.append("%s eyes" % eye_color)

	var wearing: Array[String] = []
	if not top.is_empty(): wearing.append(top)
	if not bottom.is_empty(): wearing.append(bottom)
	if not shoes.is_empty(): wearing.append(shoes)
	if not hat.is_empty(): wearing.append(hat)
	if not wearing.is_empty():
		parts.append("wearing %s" % ", ".join(wearing))

	if not accessory.is_empty():
		parts.append("with %s" % accessory)
	if not vibe.is_empty():
		parts.append(vibe + " style")

	return ", ".join(parts)

func _add_hf_token_section(parent: VBoxContainer) -> void:
	var sep := HSeparator.new()
	sep.add_theme_color_override("color", Color(0.2, 0.2, 0.25))
	parent.add_child(sep)

	var label := Label.new()
	label.text = "HuggingFace 토큰"
	label.add_theme_font_size_override("font_size", FONT_LABEL)
	label.add_theme_color_override("font_color", TEXT_COLOR)
	parent.add_child(label)

	var hint := Label.new()
	hint.text = "huggingface.co/settings/tokens 에서 발급 (최초 1회만 입력)"
	hint.add_theme_font_size_override("font_size", FONT_SUB)
	hint.add_theme_color_override("font_color", MUTED_COLOR)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	parent.add_child(hint)

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

	_hf_token_field = LineEdit.new()
	_hf_token_field.placeholder_text = "hf_..."
	_hf_token_field.secret = true
	_hf_token_field.add_theme_font_size_override("font_size", FONT_INPUT)
	_hf_token_field.add_theme_color_override("font_color", TEXT_COLOR)
	_hf_token_field.add_theme_color_override("font_placeholder_color", MUTED_COLOR)
	var empty := StyleBoxEmpty.new()
	_hf_token_field.add_theme_stylebox_override("normal",    empty)
	_hf_token_field.add_theme_stylebox_override("focus",     empty)
	_hf_token_field.add_theme_stylebox_override("read_only", empty)
	# 저장된 토큰이 있으면 미리 채워두기
	var saved := _load_saved_token()
	if not saved.is_empty():
		_hf_token_field.text = saved
	pm.add_child(_hf_token_field)

func _load_saved_token() -> String:
	const TOKEN_PATH = "user://hf_token.txt"
	if not FileAccess.file_exists(TOKEN_PATH):
		return OS.get_environment("HF_TOKEN")
	var f := FileAccess.open(TOKEN_PATH, FileAccess.READ)
	return f.get_as_text().strip_edges() if f else ""

func _add_user_name_section(parent: VBoxContainer) -> void:
	var sep := HSeparator.new()
	sep.add_theme_color_override("color", Color(0.2, 0.2, 0.25))
	parent.add_child(sep)

	var label := Label.new()
	label.text = "내 이름 (선택)"
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

	_user_name_field = LineEdit.new()
	_user_name_field.placeholder_text = "캐릭터가 나를 부를 이름"
	_user_name_field.add_theme_font_size_override("font_size", FONT_INPUT)
	_user_name_field.add_theme_color_override("font_color", TEXT_COLOR)
	_user_name_field.add_theme_color_override("font_placeholder_color", MUTED_COLOR)
	var empty := StyleBoxEmpty.new()
	_user_name_field.add_theme_stylebox_override("normal",    empty)
	_user_name_field.add_theme_stylebox_override("focus",     empty)
	_user_name_field.add_theme_stylebox_override("read_only", empty)
	pm.add_child(_user_name_field)

func _add_category_section(parent: VBoxContainer, category: Dictionary) -> void:
	var key: String = category["key"]
	var options: Array = category["options"]

	var sep := HSeparator.new()
	sep.add_theme_color_override("color", Color(0.2, 0.2, 0.25))
	parent.add_child(sep)

	var label := Label.new()
	label.text = key
	label.add_theme_font_size_override("font_size", FONT_LABEL)
	label.add_theme_color_override("font_color", TEXT_COLOR)
	parent.add_child(label)

	var flow := FlowContainer.new()
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 8)
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(flow)

	var group := ButtonGroup.new()
	for opt in options:
		var btn := Button.new()
		btn.text = opt["label"]
		btn.toggle_mode = true
		btn.button_group = group
		btn.add_theme_font_size_override("font_size", FONT_BTN)
		btn.custom_minimum_size = Vector2(0, BTN_HEIGHT)
		_apply_btn_style(btn, BTN_NORMAL, MUTED_COLOR)
		btn.toggled.connect(func(on: bool):
			if on:
				_apply_btn_style(btn, BTN_SELECTED, Color(1, 1, 1))
				_selections[key] = opt["prompt"]
			else:
				_apply_btn_style(btn, BTN_NORMAL, MUTED_COLOR)
		)
		flow.add_child(btn)

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
	if _selections.size() < PersonaData.CATEGORIES.size():
		_shake(_confirm_btn)
		return
	for key in REQUIRED_APPEARANCE:
		if not _appearance_fields.has(key):
			if _appearance_field_nodes.has(key):
				_shake(_appearance_field_nodes[key])
			else:
				_shake(_confirm_btn)
			return
	var hf_token := _hf_token_field.text.strip_edges()
	if hf_token.is_empty():
		_shake(_hf_token_field)
		return
	var tf := FileAccess.open("user://hf_token.txt", FileAccess.WRITE)
	if tf:
		tf.store_string(hf_token)
	var appearance := _build_appearance_string()
	PersonaGenerator.save_persona(name, _selections, appearance)
	var user_name := _user_name_field.text.strip_edges()
	if not user_name.is_empty():
		var profile := UserProfile.new()
		profile.set_name(user_name)
	setup_completed.emit(appearance)

func _shake(target: Control) -> void:
	var original_x := target.position.x
	var tween := create_tween()
	for i in 3:
		tween.tween_property(target, "position:x", original_x + 8, 0.05)
		tween.tween_property(target, "position:x", original_x - 8, 0.05)
	tween.tween_property(target, "position:x", original_x, 0.05)
