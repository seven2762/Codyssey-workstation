from __future__ import annotations

from dataclasses import dataclass
from typing import Any


@dataclass
class Quiz:
    """퀴즈 한 문제를 표현하는 데이터 클래스"""
    question: str       # 문제 텍스트
    choices: list[str]  # 4개의 선택지 리스트
    answer: int         # 정답 번호 (1~4)
    hint: str           # 힌트 텍스트

    def __post_init__(self) -> None:
        """객체 생성 직후 자동 호출되어 데이터 정제 및 유효성 검증을 수행한다."""
        # 앞뒤 공백 제거
        self.question = self.question.strip()
        self.choices = [choice.strip() for choice in self.choices]
        self.hint = self.hint.strip()

        # 유효성 검증 — 조건 불충족 시 ValueError 예외를 던진다
        if not self.question:
            raise ValueError("문제는 비어 있을 수 없습니다.")
        if len(self.choices) != 4:
            raise ValueError("선택지는 반드시 4개여야 합니다.")
        if any(not choice for choice in self.choices):
            raise ValueError("선택지는 비어 있을 수 없습니다.")
        if self.answer not in (1, 2, 3, 4):
            raise ValueError("정답 번호는 1~4 사이여야 합니다.")
        if not self.hint:
            raise ValueError("힌트는 비어 있을 수 없습니다.")

    def display(self, index: int | None = None) -> None:
        """문제와 선택지를 콘솔에 출력한다. index가 있으면 문제 번호도 함께 출력한다."""
        if index is not None:
            print(f"\n[{index}번 문제]")
        else:
            print()

        print(self.question)
        for i, choice in enumerate(self.choices, start=1):
            print(f"  {i}. {choice}")

    def is_correct(self, user_answer: int) -> bool:
        """사용자 입력과 정답을 비교하여 정답 여부를 반환한다."""
        return user_answer == self.answer

    def to_dict(self) -> dict[str, Any]:
        """Quiz 객체를 딕셔너리로 변환한다. (직렬화 — JSON 저장용)"""
        return {
            "question": self.question,
            "choices": self.choices,
            "answer": self.answer,
            "hint": self.hint,
        }

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> "Quiz":
        """딕셔너리를 받아서 Quiz 객체를 생성하여 반환한다. (역직렬화 — JSON 로드용)"""
        return cls(
            question=str(data["question"]),
            choices=list(data["choices"]),
            answer=int(data["answer"]),
            hint=str(data.get("hint", "기본 힌트가 없습니다.")),
        )
