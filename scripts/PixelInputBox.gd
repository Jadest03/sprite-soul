extends Control

signal text_submitted(text: String)

const C_BORDER      := Color(0.05, 0.05, 0.08, 1.0)
const C_FILL        := Color(0.94, 0.94, 1.00, 0.97)
const C_INNER       := Color(0.62, 0.72, 0.94, 1.0)
const C_PLACEHOLDER := Color(0.55, 0.55, 0.65, 0.70)
const PX            := 3
const MARGIN_X      := PX * 5
const MARGIN_Y      := PX * 4
const MIN_TEXT_W    := 210.0
const MAX_TEXT_W    := 258.0

var _edit: TextEdit
var _font: Font

func _ready() -> void:
	clip_contents = false
	_font = load("res://assets/fonts/PixelifySans-Regular.ttf")

	_edit = TextEdit.new()
	_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_edit.scroll_fit_content_height = true
	_edit.add_theme_color_override("font_color", Color(0.08, 0.08, 0.13))
	_edit.add_theme_color_override("caret_color", Color(0.08, 0.08, 0.20))
	_edit.add_theme_color_override("selection_color", Color(0.20, 0.50, 0.90, 0.5))
	_edit.add_theme_stylebox_override("normal",    StyleBoxEmpty.new())
	_edit.add_theme_stylebox_override("focus",     StyleBoxEmpty.new())
	_edit.add_theme_stylebox_override("read_only", StyleBoxEmpty.new())
	_edit.add_theme_constant_override("line_spacing", 2)
	if _font:
		_edit.add_theme_font_override("font", _font)
	_edit.add_theme_font_size_override("font_size", 15)

	_edit.gui_input.connect(_on_edit_input)
	_edit.text_changed.connect(_on_text_changed)
	add_child(_edit)

	_apply_size(MIN_TEXT_W, _line_height())

func focus_input() -> void:
	_edit.grab_focus()
	_edit.set_caret_line(0)
	_edit.set_caret_column(_edit.get_line(_edit.get_caret_line()).length())

func clear() -> void:
	_edit.text = ""
	_apply_size(MIN_TEXT_W, _line_height())
	queue_redraw()

func _on_edit_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
			var t := _edit.text.strip_edges()
			if not t.is_empty():
				text_submitted.emit(t)
			get_viewport().set_input_as_handled()

func _on_text_changed() -> void:
	var tw := _max_line_width(_edit.text)
	var content_w := clampf(maxf(tw, MIN_TEXT_W), MIN_TEXT_W, MAX_TEXT_W)
	_edit.position = Vector2(float(MARGIN_X), float(MARGIN_Y))
	_edit.size.x = content_w
	call_deferred("_sync_height")

func _sync_height() -> void:
	var lh := _line_height()
	var lspacing := _edit.get_theme_constant("line_spacing")
	var visual_lines := 0
	for i in _edit.get_line_count():
		visual_lines += 1 + _edit.get_line_wrap_count(i)
	visual_lines = maxi(visual_lines, 1)
	var content_h := lh * visual_lines + lspacing * (visual_lines - 1)
	_apply_size(_edit.size.x, maxf(content_h, lh))

func _apply_size(content_w: float, content_h: float) -> void:
	_edit.position = Vector2(float(MARGIN_X), float(MARGIN_Y))
	_edit.size = Vector2(content_w, content_h)
	size = Vector2(content_w + MARGIN_X * 2.0, content_h + MARGIN_Y * 2.0)
	queue_redraw()

func _max_line_width(t: String) -> float:
	if t.is_empty():
		return 0.0
	var font := _font if _font else _edit.get_theme_font("font")
	var fsize := _edit.get_theme_font_size("font_size")
	var max_w := 0.0
	for line in t.split("\n"):
		max_w = maxf(max_w, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x)
	return max_w

func _line_height() -> float:
	var font := _font if _font else _edit.get_theme_font("font")
	return font.get_height(_edit.get_theme_font_size("font_size"))

func _draw() -> void:
	var w := size.x
	var h := size.y
	var p := float(PX)

	draw_rect(Rect2(p*2, p*2, w - p*4, h - p*4), C_FILL)

	draw_rect(Rect2(p*2, p*2, w - p*4, p), C_INNER)
	draw_rect(Rect2(p*2, p*3, p, h - p*5), C_INNER)
	draw_rect(Rect2(w - p*3, p*3, p, h - p*5), C_INNER)

	draw_rect(Rect2(p*3, 0, w - p*6, p*2), C_BORDER)
	draw_rect(Rect2(0, p*3, p*2, h - p*6), C_BORDER)
	draw_rect(Rect2(w - p*2, p*3, p*2, h - p*6), C_BORDER)
	draw_rect(Rect2(p*3, h - p*2, w - p*6, p*2), C_BORDER)

	draw_rect(Rect2(p*2, p, p, p), C_BORDER)
	draw_rect(Rect2(p, p*2, p, p), C_BORDER)
	draw_rect(Rect2(w - p*3, p, p, p), C_BORDER)
	draw_rect(Rect2(w - p*2, p*2, p, p), C_BORDER)
	draw_rect(Rect2(p*2, h - p*2, p, p), C_BORDER)
	draw_rect(Rect2(p, h - p*3, p, p), C_BORDER)
	draw_rect(Rect2(w - p*3, h - p*2, p, p), C_BORDER)
	draw_rect(Rect2(w - p*2, h - p*3, p, p), C_BORDER)

	if _edit.text.is_empty():
		var font := _font if _font else get_theme_font("font")
		var fsize := 15
		draw_string(font,
				Vector2(float(MARGIN_X) + p, float(MARGIN_Y) + font.get_ascent(fsize)),
				"말 걸기...", HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, C_PLACEHOLDER)
