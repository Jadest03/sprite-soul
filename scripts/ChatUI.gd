extends CanvasLayer

const PersonaGenerator = preload("res://scripts/PersonaGenerator.gd")
const MemoryStore = preload("res://scripts/MemoryStore.gd")
const UserProfile = preload("res://scripts/UserProfile.gd")
const CompanionFSM = preload("res://scripts/CompanionFSM.gd")
const PixelSpeechBubble = preload("res://scripts/PixelSpeechBubble.gd")
const PixelInputBox = preload("res://scripts/PixelInputBox.gd")

const BUBBLE_HIDE_DELAY := 5.0
const TYPING_INTERVAL := 0.03
const OLLAMA_URL := "http://localhost:11434/api/chat"
const OLLAMA_MODEL := "qwen3-vl:8b-instruct"
const SCREEN_INTERVAL := 60.0
const PROACTIVE_CHANCE := 0.35
const BOREDOM_PROACTIVE_INTERVAL := 300.0

var companion: Node2D = null

var _bubble: MarginContainer
var _psb: PixelSpeechBubble
var _input_row: Control
var _pib: PixelInputBox

var _full_text := ""
var _displayed_chars := 0
var _typing_timer := 0.0
var _is_typing := false
var _hide_timer := 0.0
var _waiting := false

# 스트리밍
enum StreamPhase { IDLE, CONNECTING, SENDING, READING }
var _http_client: HTTPClient
var _stream_phase := StreamPhase.IDLE
var _pending_body := ""
var _stream_accumulator := ""
var _got_first_token := false

# 먼저 말 걸기
var _boredom_cooldown := 0.0

# 친밀도
var _affinity_exchanges: int = 0

# 하루 일기
var _diary_http: HTTPRequest
var _diary_entries: Array = []
var _diary_context: String = ""
var _pending_diary_date: String = ""

var _memory: MemoryStore
var _profile: UserProfile
var _system_prompt := ""

var _screen_context := ""
var _screen_http: HTTPRequest
var _screen_timer: Timer
var _screen_analyzing := false
var _last_proactive := ""
var _last_screen_context := ""
var _screen_perm_warned := false

func _ready() -> void:
	layer = 10
	_build_bubble()
	_build_input()
	_http_client = HTTPClient.new()
	_load_persona()
	_memory = MemoryStore.new()
	_profile = UserProfile.new()
	_load_affinity()
	_setup_diary()
	EventBus.companion_clicked.connect(_on_companion_clicked)
	_setup_screen_awareness()

func _process(delta: float) -> void:
	if companion and _bubble.visible:
		_update_bubble_position()

	if _is_typing:
		_typing_timer -= delta
		if _typing_timer <= 0.0:
			_displayed_chars = mini(_displayed_chars + 1, _full_text.length())
			_psb.set_text(_full_text.substr(0, _displayed_chars))
			if _displayed_chars >= _full_text.length():
				_is_typing = false
				_hide_timer = BUBBLE_HIDE_DELAY
			else:
				_typing_timer = TYPING_INTERVAL

	if _hide_timer > 0.0 and not _input_row.visible:
		_hide_timer -= delta
		if _hide_timer <= 0.0:
			_bubble.hide()
			_psb.set_text("")
			EventBus.chat_bubble_closed.emit()

	_poll_stream()

	if _boredom_cooldown > 0.0:
		_boredom_cooldown -= delta
	_check_boredom_proactive()

func _update_input_position() -> void:
	var vh := get_viewport().get_visible_rect().size.y
	_input_row.position = Vector2(4.0, vh - _input_row.size.y)

func _update_bubble_position() -> void:
	var pos := companion.position
	var bsize := _bubble.size
	var x := clampf(pos.x - bsize.x * 0.5, 4.0, 296.0 - bsize.x)
	var y := maxf(4.0, pos.y - companion.SPRITE_HALF.y * 1.2 - 8.0 - bsize.y)
	_bubble.position = Vector2(x, y)
	_psb.set_tail_x(pos.x - x)

func _on_companion_clicked() -> void:
	if _waiting:
		return
	if _input_row.visible:
		_set_input_visible(false)
		return
	_hide_timer = 0.0
	_set_input_visible(true)
	_pib.focus_input()
	_pib.clear()

func show_response(text: String) -> void:
	_full_text = text
	_displayed_chars = 0
	_is_typing = true
	_typing_timer = TYPING_INTERVAL
	_hide_timer = 0.0
	_psb.set_text("")
	if companion:
		_update_bubble_position()
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

func _load_persona() -> void:
	var persona := PersonaGenerator.load_persona()
	if persona.has("system_prompt"):
		_system_prompt = persona["system_prompt"]

func _send_to_ollama(user_msg: String) -> void:
	_try_extract_name(user_msg)
	_memory.add("user", user_msg)
	_affinity_exchanges += 1
	_save_affinity()
	_waiting = true
	_got_first_token = false
	_show_thinking()
	var messages := _memory.build_messages(_build_full_prompt())
	_start_stream(messages)

func _send_proactive_message() -> void:
	_waiting = true
	_got_first_token = false
	_show_thinking()
	var full_prompt := _build_full_prompt()
	full_prompt += "\n\n[대화가 한동안 없었어. 캐릭터가 자연스럽게 먼저 말을 걸어줘. 짧게 1-2문장으로.]"
	var messages := _memory.build_messages(full_prompt)
	_start_stream(messages)

func _start_stream(messages: Array) -> void:
	var body := JSON.stringify({
		"model": OLLAMA_MODEL,
		"messages": messages,
		"stream": true,
		"keep_alive": "2m",
		"options": {"num_ctx": 8192, "num_predict": 150, "temperature": 0.9}
	})
	_pending_body = body
	_stream_accumulator = ""
	_stream_phase = StreamPhase.CONNECTING
	_http_client.close()
	_http_client.connect_to_host("localhost", 11434)

func _poll_stream() -> void:
	if _stream_phase == StreamPhase.IDLE:
		return
	_http_client.poll()
	var status := _http_client.get_status()
	match _stream_phase:
		StreamPhase.CONNECTING:
			if status == HTTPClient.STATUS_CONNECTED:
				_http_client.request(HTTPClient.METHOD_POST, "/api/chat",
					PackedStringArray(["Content-Type: application/json"]), _pending_body)
				_stream_phase = StreamPhase.SENDING
			elif status == HTTPClient.STATUS_CONNECTION_ERROR:
				_stream_phase = StreamPhase.IDLE
				_on_ollama_error()
		StreamPhase.SENDING:
			if status == HTTPClient.STATUS_BODY:
				_stream_phase = StreamPhase.READING
			elif status == HTTPClient.STATUS_CONNECTION_ERROR:
				_stream_phase = StreamPhase.IDLE
				_on_ollama_error()
		StreamPhase.READING:
			if status == HTTPClient.STATUS_BODY:
				var chunk := _http_client.read_response_body_chunk()
				if chunk.size() > 0:
					_parse_stream_chunk(chunk.get_string_from_utf8())
			elif status == HTTPClient.STATUS_DISCONNECTED:
				_stream_phase = StreamPhase.IDLE
				if _waiting:
					_on_ollama_error()

func _parse_stream_chunk(text: String) -> void:
	_stream_accumulator += text
	var lines := _stream_accumulator.split("\n")
	_stream_accumulator = lines[-1]
	for i in range(lines.size() - 1):
		var line := lines[i].strip_edges()
		if line.is_empty():
			continue
		var parsed: Variant = JSON.parse_string(line)
		if not parsed is Dictionary:
			continue
		var content: String = parsed.get("message", {}).get("content", "")
		var done: bool = parsed.get("done", false)
		if not content.is_empty():
			if not _got_first_token:
				_got_first_token = true
				_full_text = ""
			_full_text += content
			_psb.set_text(_full_text)
			_bubble.show()
		if done:
			_stream_phase = StreamPhase.IDLE
			_waiting = false
			if not _full_text.is_empty():
				_memory.add("assistant", _full_text)
				EventBus.chat_response_received.emit(_full_text)
				_hide_timer = BUBBLE_HIDE_DELAY

func _build_full_prompt() -> String:
	var p := _system_prompt + _profile.to_prompt_fragment() + _affinity_fragment()
	if not _diary_context.is_empty():
		p += "\n\n[지난 기억]\n" + _diary_context
	if not _screen_context.is_empty():
		p += "\n\n[현재 화면]\n" + _screen_context
	return p

# ── 친밀도 ────────────────────────────────────────────────

const _AFFINITY_PATH = "user://affinity.json"

func _load_affinity() -> void:
	if not FileAccess.file_exists(_AFFINITY_PATH):
		return
	var f := FileAccess.open(_AFFINITY_PATH, FileAccess.READ)
	if not f:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		_affinity_exchanges = int(parsed.get("exchanges", 0))

func _save_affinity() -> void:
	var f := FileAccess.open(_AFFINITY_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"exchanges": _affinity_exchanges}))
		f.close()

func _affinity_fragment() -> String:
	if _affinity_exchanges < 5:
		return "\n[우리는 처음 만난 사이야. 조금 조심스럽게 대해줘.]"
	elif _affinity_exchanges < 20:
		return "\n[우리는 알아가는 중이야 (%d회 대화). 편하게 대해줘.]" % _affinity_exchanges
	elif _affinity_exchanges < 50:
		return "\n[우리는 꽤 친한 친구야 (%d회 대화). 자연스럽고 친근하게.]" % _affinity_exchanges
	else:
		return "\n[우리는 오랜 친구야 (%d회 대화). 아주 편하게, 농담도 해.]" % _affinity_exchanges

# ── 하루 일기 ─────────────────────────────────────────────

const _DIARY_PATH      = "user://diary.json"
const _LAST_DATE_PATH  = "user://last_session_date.txt"

func _setup_diary() -> void:
	_diary_http = HTTPRequest.new()
	add_child(_diary_http)
	_diary_http.request_completed.connect(_on_diary_summarized)
	_load_diary()
	_build_diary_context()
	get_tree().create_timer(2.0).timeout.connect(_check_new_day)

func _load_diary() -> void:
	if not FileAccess.file_exists(_DIARY_PATH):
		return
	var f := FileAccess.open(_DIARY_PATH, FileAccess.READ)
	if not f:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Array:
		_diary_entries = parsed

func _build_diary_context() -> void:
	if _diary_entries.is_empty():
		return
	var recent := _diary_entries.slice(maxi(0, _diary_entries.size() - 3))
	var lines := ""
	for entry in recent:
		lines += "%s: %s\n" % [entry.get("date", ""), entry.get("summary", "")]
	_diary_context = lines.strip_edges()

func _check_new_day() -> void:
	var today := Time.get_date_string_from_system()
	var last := ""
	if FileAccess.file_exists(_LAST_DATE_PATH):
		var f := FileAccess.open(_LAST_DATE_PATH, FileAccess.READ)
		if f:
			last = f.get_as_text().strip_edges()
			f.close()
	var fw := FileAccess.open(_LAST_DATE_PATH, FileAccess.WRITE)
	if fw:
		fw.store_string(today)
		fw.close()
	if not last.is_empty() and last != today:
		_request_diary_summary(last)

func _request_diary_summary(date: String) -> void:
	var history := _memory.get_persistent()
	if history.size() < 2:
		return
	_pending_diary_date = date
	var history_text := ""
	for msg in history:
		var role: String = "나" if msg.role == "user" else "캐릭터"
		history_text += "%s: %s\n" % [role, msg.get("content", "")]
	var prompt := "다음 대화를 한 문장으로 간결하게 요약해줘. 주요 주제나 감정 위주로, 한국어로:\n\n" + history_text
	var body := JSON.stringify({
		"model": OLLAMA_MODEL,
		"messages": [{"role": "user", "content": prompt}],
		"stream": false,
		"options": {"num_ctx": 4096, "num_predict": 60, "temperature": 0.5}
	})
	_diary_http.request(OLLAMA_URL, ["Content-Type: application/json"], HTTPClient.METHOD_POST, body)

func _on_diary_summarized(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if code != 200:
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not parsed is Dictionary:
		return
	var summary: String = parsed.get("message", {}).get("content", "").strip_edges()
	if summary.is_empty() or _pending_diary_date.is_empty():
		return
	_diary_entries.append({"date": _pending_diary_date, "summary": summary})
	if _diary_entries.size() > 30:
		_diary_entries = _diary_entries.slice(_diary_entries.size() - 30)
	var f := FileAccess.open(_DIARY_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_diary_entries))
		f.close()
	_build_diary_context()

func _check_boredom_proactive() -> void:
	if _boredom_cooldown > 0.0 or companion == null:
		return
	if _waiting or _stream_phase != StreamPhase.IDLE or _bubble.visible or _input_row.visible:
		return
	if not companion.emotion.is_bored():
		return
	if companion.fsm.current_state == CompanionFSM.State.SLEEP:
		return
	companion.emotion.boredom = 0.0
	_boredom_cooldown = BOREDOM_PROACTIVE_INTERVAL
	_send_proactive_message()

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

# --- 화면 인식 ---

func _setup_screen_awareness() -> void:
	_screen_http = HTTPRequest.new()
	add_child(_screen_http)
	_screen_http.request_completed.connect(_on_screen_analyzed)
	# Defer permission check so the companion renders first
	get_tree().create_timer(1.0).timeout.connect(_start_screen_capture)

func _start_screen_capture() -> void:
	_screen_timer = Timer.new()
	_screen_timer.wait_time = SCREEN_INTERVAL
	_screen_timer.one_shot = false
	_screen_timer.timeout.connect(_capture_and_analyze)
	add_child(_screen_timer)
	_screen_timer.start()

func _capture_and_analyze() -> void:
	var is_sleeping: bool = companion != null and companion.fsm.current_state == CompanionFSM.State.SLEEP
	if _screen_analyzing or _waiting or _is_typing or is_sleeping:
		return
	var path := "/tmp/sprite_soul_screen.png"
	var helper := OS.get_executable_path().get_base_dir().path_join("sc_helper")
	var code := OS.execute(helper, [path], [])
	if code == 2:
		_screen_timer.stop()
		if not _screen_perm_warned:
			_screen_perm_warned = true
			get_tree().create_timer(0.5).timeout.connect(func():
				var msg := "화면 기록 권한이 없어요! 시스템 설정 → 개인정보 보호 및 보안 → 화면 기록에서 SpriteSoul을 허용 후 재시작해주세요."
				show_response(msg)
				EventBus.chat_response_received.emit(msg))
		return
	if code != 0 or not FileAccess.file_exists(path):
		return
	OS.execute("/usr/bin/sips", ["-Z", "1280", path])
	_analyze_screen(path)

func _analyze_screen(path: String) -> void:
	_screen_analyzing = true
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		_screen_analyzing = false
		return
	var b64 := Marshalls.raw_to_base64(file.get_buffer(file.get_length()))
	file.close()

	var persona_name: String = PersonaGenerator.load_persona().get("name", "나")
	var prompt := (
		"Look at this screenshot and answer in Korean with exactly this format:\n"
		+ "CONTEXT: [what the user is doing, one line]\n"
		+ "COMMENT: [a casual remark from " + persona_name + "'s perspective in informal Korean, or leave blank]\n\n"
		+ "Example:\nCONTEXT: 유튜브로 영상 보는 중\nCOMMENT: 야 뭐 보고 있어?"
	)
	var body := JSON.stringify({
		"model": OLLAMA_MODEL,
		"messages": [{"role": "user", "content": prompt, "images": [b64]}],
		"stream": false,
		"keep_alive": "2m",
		"options": {"num_ctx": 4096, "num_predict": 80, "temperature": 0.7}
	})
	var err := _screen_http.request(OLLAMA_URL, ["Content-Type: application/json"], HTTPClient.METHOD_POST, body)
	if err != OK:
		_screen_analyzing = false

func _on_screen_analyzed(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_screen_analyzing = false
	if response_code != 200:
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not parsed is Dictionary:
		return
	var reply: String = parsed.get("message", {}).get("content", "")
	var comment := ""
	for line in reply.split("\n"):
		var s := line.strip_edges()
		if s.begins_with("CONTEXT:"):
			_screen_context = s.substr(8).strip_edges()
		elif s.begins_with("COMMENT:"):
			comment = s.substr(8).strip_edges()
	var context_changed := _screen_context != _last_screen_context
	_last_screen_context = _screen_context
	var is_sleeping: bool = companion != null and companion.fsm.current_state == CompanionFSM.State.SLEEP
	if not comment.is_empty() and comment != _last_proactive and context_changed \
			and randf() < PROACTIVE_CHANCE and not _waiting and _stream_phase == StreamPhase.IDLE \
			and not _input_row.visible and not is_sleeping:
		_last_proactive = comment
		_memory.add("assistant", comment)
		EventBus.chat_response_received.emit(comment)
		show_response(comment)

func _show_thinking() -> void:
	_full_text = "..."
	_displayed_chars = 3
	_is_typing = false
	_hide_timer = 0.0
	_psb.set_text("...")
	if companion:
		_update_bubble_position()
	_bubble.show()

func _on_ollama_error() -> void:
	_waiting = false
	_stream_phase = StreamPhase.IDLE
	show_response("(연결 안 됨)")
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
	_psb = PixelSpeechBubble.new()
	_bubble = _psb
	_bubble.hide()
	add_child(_bubble)

func _build_input() -> void:
	_pib = PixelInputBox.new()
	_input_row = _pib
	_pib.hide()
	_pib.text_submitted.connect(_on_input_submitted)
	_pib.resized.connect(_update_input_position)
	add_child(_pib)
