extends RefCounted

const SAVE_PATH = "user://memory.json"
const MAX_SESSION = 20   # 세션 내 컨텍스트로 보낼 최대 메시지 수
const MAX_PERSIST = 10   # 파일에 저장할 최대 메시지 수

var _session: Array = []    # 현재 세션 전체 히스토리
var _persistent: Array = [] # 이전 세션 포함 저장된 기억

func _init() -> void:
	_load()
	# 이전 세션 기억을 현재 세션 컨텍스트로 시작
	_session = _persistent.duplicate()

func add(role: String, content: String) -> void:
	var msg := {"role": role, "content": content}
	_session.append(msg)
	_persistent.append(msg)
	if _persistent.size() > MAX_PERSIST:
		_persistent = _persistent.slice(_persistent.size() - MAX_PERSIST)
	_save()

# Ollama에 보낼 전체 messages 배열 반환 (system prompt 포함)
func build_messages(system_prompt: String) -> Array:
	var msgs: Array = [{"role": "system", "content": system_prompt}]
	var history := _session
	if history.size() > MAX_SESSION:
		history = history.slice(history.size() - MAX_SESSION)
	msgs.append_array(history)
	return msgs

func _save() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(_persistent))
		file.close()

func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Array:
		_persistent = parsed
