"""
SpriteSoul fine-tuning dataset builder.
Outputs: data_gen/train_samples.jsonl
"""

import json
import pathlib

from samples import PERSONAS, SAMPLES

SYSTEM_TEMPLATE = """너의 이름은 {name}이야.
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


def build_example(persona_key: str, user_msg: str, assistant_msg: str) -> dict:
    p = PERSONAS[persona_key]
    system = SYSTEM_TEMPLATE.format(
        name=p["name"],
        성격=p["성격"],
        말투=p["말투"],
        특징=p["특징"],
        **{"감정 표현": p["감정 표현"]},
        관계=p["관계"],
    )
    return {
        "messages": [
            {"role": "system",    "content": system},
            {"role": "user",      "content": user_msg},
            {"role": "assistant", "content": assistant_msg},
        ]
    }


def validate(examples: list[dict]) -> None:
    for i, ex in enumerate(examples):
        msgs = ex.get("messages", [])
        assert len(msgs) == 3, f"example {i}: expected 3 messages"
        assert msgs[0]["role"] == "system"
        assert msgs[1]["role"] == "user"
        assert msgs[2]["role"] == "assistant"
        assert msgs[2]["content"].strip(), f"example {i}: empty assistant response"
    print(f"validation passed — {len(examples)} examples")


def save_jsonl(examples: list[dict], path: pathlib.Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as f:
        for ex in examples:
            f.write(json.dumps(ex, ensure_ascii=False) + "\n")
    print(f"saved → {path}  ({path.stat().st_size // 1024} KB)")


if __name__ == "__main__":
    examples = [build_example(*s) for s in SAMPLES]
    validate(examples)
    out = pathlib.Path(__file__).parent / "train_samples.jsonl"
    save_jsonl(examples, out)
