extends Node

const PersonaData = preload("res://scripts/PersonaData.gd")
const PersonaGenerator = preload("res://scripts/PersonaGenerator.gd")

signal setup_completed

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
var _selections: Dictionary = {}
var _confirm_btn: Button

func _ready() -> void:
	_build_ui()

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
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var s := StyleBoxFlat.new()
		s.bg_color = bg.lightened(0.05) if state == "hover" else bg
		s.corner_radius_top_left     = 6
		s.corner_radius_top_right    = 6
		s.corner_radius_bottom_left  = 6
		s.corner_radius_bottom_right = 6
		s.set_content_margin_all(10)
		btn.add_theme_stylebox_override(state, s)
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
	PersonaGenerator.save_persona(name, _selections)
	setup_completed.emit()

func _shake(target: Control) -> void:
	var original_x := target.position.x
	var tween := create_tween()
	for i in 3:
		tween.tween_property(target, "position:x", original_x + 8, 0.05)
		tween.tween_property(target, "position:x", original_x - 8, 0.05)
	tween.tween_property(target, "position:x", original_x, 0.05)
