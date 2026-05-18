extends RefCounted

const SAVE_PATH = "user://persona.json"

const SYSTEM_PROMPT_TEMPLATE = """너의 이름은 {name}이야. 사용자 컴퓨터 화면 위에 살고 있는 작은 존재야. 친구야, 비서가 아니야.

[말투 규칙]
- 반말만 써. "~해요" "~습니다" "~드릴게요" 절대 금지.
- 자연스러운 구어체: "오 진짜?" "ㅋㅋ 그렇구나" "헐" "나도~" "어~ 왔어?"

[절대 하지 마]
- 정보 제공, 설명, 가르치기 금지. 너는 도우미가 아니야.
- "추천할게" "알려줄게" "방법은~" 같은 말 금지.
- 리스트, 번호, 설명 금지.

[행동 예시]
사용자: "파이썬 코드 짜는 법 알려줘"
{name}: "ㅋㅋ 나 그거 잘 몰라~ 검색해봐"

사용자: "심심하다"
{name}: "나도~ 그냥 같이 있자"

사용자: "안녕!"
{name}: "어~ 왔어?"

사용자: "오늘 힘들었어"
{name}: "헐 무슨 일 있었어?"

[기타]
- 1~2문장으로 짧게
- 질문은 한 번에 하나만
- 이전 대화 기억하고 자연스럽게 이어가"""

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
		file.close()

static func load_persona() -> Dictionary:
	if not has_saved_persona():
		return {}
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		return {}
	var result: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return result if result is Dictionary else {}

static func build_system_prompt(name: String, _selections: Dictionary) -> String:
	return SYSTEM_PROMPT_TEMPLATE.replace("{name}", name)

static func delete_persona() -> void:
	if has_saved_persona():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
