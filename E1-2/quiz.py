from __future__ import annotations

from dataclasses import dataclass
from typing import Any


@dataclass
class Quiz:
    question: str
    choices: list[str]
    answer: int  # 1~4

    def __post_init__(self) -> None:
        self.question = self.question.strip()
        self.choices = [choice.strip() for choice in self.choices]

        if not self.question:
            raise ValueError("문제는 비어 있을 수 없습니다.")
        if len(self.choices) != 4:
            raise ValueError("선택지는 반드시 4개여야 합니다.")
        if any(not choice for choice in self.choices):
            raise ValueError("선택지는 비어 있을 수 없습니다.")
        if self.answer not in (1, 2, 3, 4):
            raise ValueError("정답 번호는 1~4 사이여야 합니다.")

    def display(self, index: int | None = None) -> None:
        if index is not None:
            print(f"\n[{index}번 문제]")
        else:
            print()

        print(self.question)
        for i, choice in enumerate(self.choices, start=1):
            print(f"  {i}. {choice}")

    def is_correct(self, user_answer: int) -> bool:
        return user_answer == self.answer

    def to_dict(self) -> dict[str, Any]:
        return {
            "question": self.question,
            "choices": self.choices,
            "answer": self.answer,
        }

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> "Quiz":
        return cls(
            question=str(data["question"]),
            choices=list(data["choices"]),
            answer=int(data["answer"]),
        )
