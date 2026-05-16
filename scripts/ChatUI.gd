extends CanvasLayer

const PersonaGenerator = preload("res://scripts/PersonaGenerator.gd")
const MemoryStore = preload("res://scripts/MemoryStore.gd")
const UserProfile = preload("res://scripts/UserProfile.gd")

const BUBBLE_HIDE_DELAY := 5.0
const TYPING_INTERVAL := 0.03
const OLLAMA_URL := "http://localhost:11434/api/chat"
const OLLAMA_MODEL := "sprite-soul"

var companion: Node2D = null

var _bubble: PanelContainer
var _bubble_label: Label
var _input_row: PanelContainer
var _input_field: LineEdit
var _http: HTTPRequest

var _full_text := ""
var _displayed_chars := 0
var _typing_timer := 0.0
var _is_typing := false
var _hide_timer := 0.0
var _waiting := false

var _memory: MemoryStore
var _profile: UserProfile
var _system_prompt := ""

func _ready() -> void:
	layer = 10
	_build_bubble()
	_build_input()
	_setup_http()
	_load_persona()
	_memory = MemoryStore.new()
	_profile = UserProfile.new()
	EventBus.companion_clicked.connect(_on_companion_clicked)
	EventBus.chat_response_received.connect(show_response)

func _process(delta: float) -> void:
	if companion and _bubble.visible:
		_update_bubble_position()

	if _is_typing:
		_typing_timer -= delta
		if _typing_timer <= 0.0:
			_displayed_chars = mini(_displayed_chars + 1, _full_text.length())
			_bubble_label.text = _full_text.substr(0, _displayed_chars)
			if _displayed_chars >= _full_text.length():
				_is_typing = false
				_hide_timer = BUBBLE_HIDE_DELAY
			else:
				_typing_timer = TYPING_INTERVAL

	if _hide_timer > 0.0 and not _input_row.visible:
		_hide_timer -= delta
		if _hide_timer <= 0.0:
			_bubble.hide()

func _update_input_position() -> void:
	var vh := get_viewport().get_visible_rect().size.y
	_input_row.position = Vector2(4.0, vh - _input_row.size.y - 4.0)

func _update_bubble_position() -> void:
	var pos := companion.position
	var bsize := _bubble.size
	var x := clampf(pos.x - bsize.x * 0.5, 4.0, 296.0 - bsize.x)
	var y := maxf(4.0, pos.y - 120.0 - bsize.y)
	_bubble.position = Vector2(x, y)

func _on_companion_clicked() -> void:
	if _waiting:
		return
	if _input_row.visible:
		_set_input_visible(false)
		return
	_hide_timer = 0.0
	_set_input_visible(true)
	_input_field.grab_focus()
	_input_field.clear()

func show_response(text: String) -> void:
	_full_text = text
	_displayed_chars = 0
	_is_typing = true
	_typing_timer = TYPING_INTERVAL
	_hide_timer = 0.0
	_bubble_label.text = ""
	_bubble.show()
	_set_input_visible(false)

func _on_input_submitted(text: String) -> void:
	var trimmed := text.strip_edges()
	if trimmed.is_empty():
		return
	_set_input_visible(false)
	EventBus.chat_requested.emit(trimmed)
	_send_to_ollama(trimmed)

# --- Ollama 연결 ---

func _setup_http() -> void:
	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_http_completed)

func _load_persona() -> void:
	var persona := PersonaGenerator.load_persona()
	if persona.has("system_prompt"):
		_system_prompt = persona["system_prompt"]

func _send_to_ollama(user_msg: String) -> void:
	_try_extract_name(user_msg)
	_memory.add("user", user_msg)
	_waiting = true
	_show_thinking()

	var full_prompt := _system_prompt + _profile.to_prompt_fragment()
	var messages := _memory.build_messages(full_prompt)
	var body := JSON.stringify({
		"model": OLLAMA_MODEL,
		"messages": messages,
		"stream": false
	})
	var err := _http.request(OLLAMA_URL, ["Content-Type: application/json"], HTTPClient.METHOD_POST, body)
	if err != OK:
		_on_ollama_error()

func _try_extract_name(text: String) -> void:
	# "내 이름은 X야", "나는 X야", "X라고 불러줘" 패턴 감지
	var patterns := [
		["내 이름은 ", ["야", "이야", "이에요", "예요"]],
		["저는 ", ["이에요", "예요", "이야", "야"]],
		["나는 ", ["야", "이야"]],
	]
	for pair in patterns:
		var prefix: String = pair[0]
		var suffixes: Array = pair[1]
		var idx := text.find(prefix)
		if idx < 0:
			continue
		var rest := text.substr(idx + prefix.length())
		for suffix in suffixes:
			var end := rest.find(suffix)
			if end > 0 and end <= 6:
				var name := rest.substr(0, end).strip_edges()
				if name.length() >= 1:
					_profile.set_name(name)
					return

func _on_http_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_waiting = false
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		_on_ollama_error()
		return

	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not parsed is Dictionary:
		_on_ollama_error()
		return

	var reply: String = parsed.get("message", {}).get("content", "")
	if reply.is_empty():
		_on_ollama_error()
		return

	_memory.add("assistant", reply)
	EventBus.chat_response_received.emit(reply)

func _show_thinking() -> void:
	_full_text = "..."
	_displayed_chars = 3
	_is_typing = false
	_hide_timer = 0.0
	_bubble_label.text = "..."
	_bubble.show()

func _on_ollama_error() -> void:
	_waiting = false
	EventBus.chat_response_received.emit("(연결 안 됨)")

func _set_input_visible(visible: bool) -> void:
	EventBus.chat_input_open = visible
	if visible:
		_update_input_position()
	_input_row.visible = visible
	if not visible and _bubble.visible and not _is_typing and _hide_timer == 0.0:
		_hide_timer = BUBBLE_HIDE_DELAY

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if _input_row.visible:
			_set_input_visible(false)

# --- UI 빌드 ---

func _build_bubble() -> void:
	_bubble = PanelContainer.new()
	_bubble.custom_minimum_size = Vector2(160, 0)
	_bubble.hide()
	add_child(_bubble)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.12, 0.90)
	style.corner_radius_top_left    = 10
	style.corner_radius_top_right   = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	style.set_content_margin_all(0)
	_bubble.add_theme_stylebox_override("panel", style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left",   12)
	margin.add_theme_constant_override("margin_right",  12)
	margin.add_theme_constant_override("margin_top",    8)
	margin.add_theme_constant_override("margin_bottom", 8)
	_bubble.add_child(margin)

	_bubble_label = Label.new()
	_bubble_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bubble_label.add_theme_color_override("font_color", Color.WHITE)
	_bubble_label.add_theme_font_size_override("font_size", 17)
	_bubble_label.custom_minimum_size = Vector2(180, 0)
	margin.add_child(_bubble_label)

func _build_input() -> void:
	_input_row = PanelContainer.new()
	_input_row.size = Vector2(292, 44)
	_input_row.hide()
	add_child(_input_row)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.12, 0.90)
	style.corner_radius_top_left    = 6
	style.corner_radius_top_right   = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.set_content_margin_all(0)
	_input_row.add_theme_stylebox_override("panel", style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left",   8)
	margin.add_theme_constant_override("margin_right",  8)
	margin.add_theme_constant_override("margin_top",    5)
	margin.add_theme_constant_override("margin_bottom", 5)
	_input_row.add_child(margin)

	_input_field = LineEdit.new()
	_input_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input_field.placeholder_text = "말 걸기..."
	_input_field.add_theme_font_size_override("font_size", 15)
	_input_field.add_theme_color_override("font_color", Color.WHITE)
	_input_field.add_theme_color_override("font_placeholder_color", Color(0.55, 0.55, 0.6))
	var empty := StyleBoxEmpty.new()
	_input_field.add_theme_stylebox_override("normal",    empty)
	_input_field.add_theme_stylebox_override("focus",     empty)
	_input_field.add_theme_stylebox_override("read_only", empty)
	_input_field.text_submitted.connect(_on_input_submitted)
	margin.add_child(_input_field)
