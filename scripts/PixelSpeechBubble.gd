extends MarginContainer

const C_BORDER := Color(0.05, 0.05, 0.08, 1.0)
const C_FILL   := Color(0.94, 0.94, 1.00, 0.97)
const C_INNER  := Color(0.62, 0.72, 0.94, 1.0)
const PX         := 3
const TOP_HW     := PX * 3   # tail half-width at top (9px)
const STEPS      := 4        # tail staircase steps
const MAX_TEXT_W := 200.0    # px before text wraps
const MARGIN_X   := PX * 5  # horizontal margin on each side
const MARGIN_Y   := PX * 4  # vertical margin on each side

var label: Label
var _font: Font
var _tail_x: float = -1.0  # -1 = use center; set via set_tail_x()

func _ready() -> void:
	clip_contents = false
	add_theme_constant_override("margin_left",   MARGIN_X)
	add_theme_constant_override("margin_right",  MARGIN_X)
	add_theme_constant_override("margin_top",    MARGIN_Y)
	add_theme_constant_override("margin_bottom", MARGIN_Y)

	_font = load("res://assets/fonts/PixelifySans-Regular.ttf")
	label = Label.new()
	label.add_theme_color_override("font_color", Color(0.08, 0.08, 0.13))
	label.add_theme_font_size_override("font_size", 15)
	if _font:
		label.add_theme_font_override("font", _font)
	add_child(label)
	resized.connect(queue_redraw)

func set_tail_x(tx: float) -> void:
	if is_equal_approx(tx, _tail_x):
		return
	_tail_x = tx
	queue_redraw()

func set_text(t: String) -> void:
	var tw := _text_width(t)
	if tw <= MAX_TEXT_W:
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.custom_minimum_size = Vector2(0, 0)
		# Set size directly so the bubble shrinks/grows immediately each character
		size = Vector2(maxf(tw, 1.0) + MARGIN_X * 2, _line_height() + MARGIN_Y * 2)
	else:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size = Vector2(MAX_TEXT_W, 0)
		# Let the layout system compute wrapped height next frame
		call_deferred("reset_size")
	label.text = t
	queue_redraw()

func _text_width(t: String) -> float:
	if t.is_empty():
		return 0.0
	var font := _font if _font else label.get_theme_font("font")
	return font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1,
			label.get_theme_font_size("font_size")).x

func _line_height() -> float:
	var font := _font if _font else label.get_theme_font("font")
	return font.get_height(label.get_theme_font_size("font_size"))

func _draw() -> void:
	var w := size.x
	var h := size.y
	var p := float(PX)
	var hw := float(TOP_HW)
	var raw_tc := _tail_x if _tail_x >= 0.0 else w * 0.5
	var tc := clampf(raw_tc, hw + p * 3.0, w - hw - p * 3.0)

	# Body fill
	draw_rect(Rect2(p*2, p*2, w - p*4, h - p*4), C_FILL)

	# Inner blue border (top + left + right)
	draw_rect(Rect2(p*2, p*2, w - p*4, p), C_INNER)
	draw_rect(Rect2(p*2, p*3, p, h - p*5), C_INNER)
	draw_rect(Rect2(w - p*3, p*3, p, h - p*5), C_INNER)

	# Border edges (stop short by 2 pixel units → 3-step rounding)
	draw_rect(Rect2(p*3, 0, w - p*6, p*2), C_BORDER)
	draw_rect(Rect2(0, p*3, p*2, h - p*6), C_BORDER)
	draw_rect(Rect2(w - p*2, p*3, p*2, h - p*6), C_BORDER)
	draw_rect(Rect2(p*3, h - p*2, tc - hw - p*3, p*2), C_BORDER)
	draw_rect(Rect2(tc + hw, h - p*2, w - tc - hw - p*3, p*2), C_BORDER)

	# Corner connectors (2 per corner → 3-step staircase)
	draw_rect(Rect2(p*2, p, p, p), C_BORDER)      # top-left  A
	draw_rect(Rect2(p, p*2, p, p), C_BORDER)       # top-left  B
	draw_rect(Rect2(w - p*3, p, p, p), C_BORDER)   # top-right A
	draw_rect(Rect2(w - p*2, p*2, p, p), C_BORDER) # top-right B
	draw_rect(Rect2(p*2, h - p*2, p, p), C_BORDER) # bot-left  A
	draw_rect(Rect2(p, h - p*3, p, p), C_BORDER)   # bot-left  B
	draw_rect(Rect2(w - p*3, h - p*2, p, p), C_BORDER) # bot-right A
	draw_rect(Rect2(w - p*2, h - p*3, p, p), C_BORDER) # bot-right B

	# Fill the tail gap
	draw_rect(Rect2(tc - hw, h - p*2, hw * 2, p*2), C_FILL)

	# Tail staircase (pointing down)
	for i in STEPS + 1:
		var chw := hw - i * p
		var ty := h + i * p * 2
		if chw < 0:
			break
		draw_rect(Rect2(tc - chw - p, ty, (chw + p) * 2, p * 2), C_BORDER)
		if chw > 0:
			draw_rect(Rect2(tc - chw, ty, chw * 2, p * 2), C_FILL)
