extends RefCounted

const SAVE_PATH = "user://user_profile.json"
const MAX_NOTES = 10

var user_name: String = ""
var notes: Array = []  # ["좋아하는 음식: 라면", "직업: 개발자", ...]

func _init() -> void:
	_load()

func set_name(n: String) -> void:
	if n == user_name:
		return
	user_name = n
	_save()

func add_note(note: String) -> void:
	if note in notes:
		return
	notes.append(note)
	if notes.size() > MAX_NOTES:
		notes = notes.slice(notes.size() - MAX_NOTES)
	_save()

func to_prompt_fragment() -> String:
	if user_name.is_empty() and notes.is_empty():
		return ""
	var lines: Array = []
	if not user_name.is_empty():
		lines.append("사용자 이름: " + user_name)
	for note in notes:
		lines.append(note)
	return "\n\n[사용자 정보]\n" + "\n".join(lines)

func _save() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({"name": user_name, "notes": notes}))

func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return
	user_name = parsed.get("name", "")
	notes = parsed.get("notes", [])
