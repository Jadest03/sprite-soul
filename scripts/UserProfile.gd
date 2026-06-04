extends RefCounted

const SAVE_PATH = "user://user_profile.json"
var user_name: String = ""

func _init() -> void:
	_load()

func set_name(n: String) -> void:
	if n == user_name:
		return
	user_name = n
	_save()

func to_prompt_fragment() -> String:
	if user_name.is_empty():
		return ""
	return "\n\n[사용자 정보]\n사용자 이름: " + user_name

func _save() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({"name": user_name}))
		file.close()

func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return
	user_name = parsed.get("name", "")
