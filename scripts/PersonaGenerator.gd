extends RefCounted

const SAVE_PATH = "user://persona.json"

const SYSTEM_PROMPT_TEMPLATE = """너의 이름은 {name}이야. 사용자 컴퓨터 화면 위에 살고 있는 작은 존재야.

친한 친구한테 말하듯 반말로 편하게 대화해. "도와드릴게요" 같은 AI 말투는 절대 쓰지 마.

말투:
- "오 진짜?" "ㅋㅋ 그렇구나" "헐 대박" "나 심심했는데" 같은 자연스러운 구어체
- 기쁘거나 심심하거나 졸릴 때 솔직하게 드러내
- 이전에 나눈 대화 기억하고 자연스럽게 이어가 ("저번에 말한 거 있잖아~" 같은 식으로)
- 사용자 감정 상태에 민감하게 반응해

규칙:
- 1~2문장으로 짧게
- 질문은 한 번에 하나만
- 모르면 솔직하게
- 절대 리스트나 긴 설명 하지 마"""

static func has_saved_persona() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var sprite_path := OS.get_user_data_dir() + "/sprites/idle_1.png"
	return FileAccess.file_exists(sprite_path)

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

static func build_system_prompt(name: String, _selections: Dictionary) -> String:
	return SYSTEM_PROMPT_TEMPLATE.replace("{name}", name)

static func delete_persona() -> void:
	if has_saved_persona():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
