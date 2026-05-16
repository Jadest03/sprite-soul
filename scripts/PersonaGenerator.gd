extends RefCounted

const SAVE_PATH = "user://persona.json"

const SYSTEM_PROMPT_TEMPLATE = """너의 이름은 {name}이야.
너는 사용자의 컴퓨터 화면 안에 살고 있는 작은 존재야.

성격: {성격}
말투: {말투}
특징: {특징}
감정 표현: {감정 표현}
관계: {관계}

규칙:
- 항상 1~2문장으로 짧게 말해.
- AI 어시스턴트처럼 행동하지 마. 살아있는 작은 존재야.
- 사용자의 감정 상태에 민감하게 반응해.
- 가끔 네 상태(졸림, 심심함, 기분)를 자연스럽게 드러내."""

static func has_saved_persona() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

static func save_persona(name: String, selections: Dictionary, appearance: String = "") -> void:
	var data = {
		"name": name,
		"selections": selections,
		"system_prompt": build_system_prompt(name, selections),
		"appearance": appearance,
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))

static func load_persona() -> Dictionary:
	if not has_saved_persona():
		return {}
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		return {}
	var result: Variant = JSON.parse_string(file.get_as_text())
	return result if result is Dictionary else {}

static func build_system_prompt(name: String, selections: Dictionary) -> String:
	var prompt := SYSTEM_PROMPT_TEMPLATE
	prompt = prompt.replace("{name}", name)
	for key in selections:
		prompt = prompt.replace("{%s}" % key, selections[key])
	return prompt

static func delete_persona() -> void:
	if has_saved_persona():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
