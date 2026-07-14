"""모델과 CLI가 공유하는 입력 검증 함수."""

from __future__ import annotations

from collections.abc import Iterable
from datetime import datetime
from os import PathLike, fspath
from pathlib import Path
from typing import Literal, cast

from .errors import ValidationError

TransactionType = Literal["income", "expense"]


def validate_path(value: str | PathLike[str], field_name: str = "경로") -> Path:
    try:
        raw_path = fspath(value)
    except TypeError as error:
        raise ValidationError(f"{field_name}가 올바르지 않습니다.", f"유효한 {field_name}를 입력해 주세요.") from error
    if not isinstance(raw_path, str) or not raw_path.strip():
        raise ValidationError(f"{field_name}는 비어 있을 수 없습니다.", f"유효한 {field_name}를 입력해 주세요.")
    if "\x00" in raw_path:
        raise ValidationError(f"{field_name}에 NUL 문자를 사용할 수 없습니다.", f"유효한 {field_name}를 입력해 주세요.")
    return Path(raw_path)


def validate_date(value: object, field_name: str = "날짜") -> str:
    if not isinstance(value, str):
        raise ValidationError(
            f"{field_name}는 문자열이어야 합니다: {value!r}",
            "YYYY-MM-DD 형식의 날짜를 입력해 주세요.",
        )
    value = value.strip()
    try:
        parsed = datetime.strptime(value, "%Y-%m-%d")
    except (TypeError, ValueError) as error:
        raise ValidationError(
            f"{field_name} 형식이 올바르지 않습니다: {value!r}",
            "YYYY-MM-DD 형식의 실제 날짜를 입력해 주세요.",
        ) from error
    if parsed.strftime("%Y-%m-%d") != value:
        raise ValidationError(
            f"{field_name} 형식이 올바르지 않습니다: {value!r}",
            "YYYY-MM-DD 형식으로 월과 일을 두 자리로 입력해 주세요.",
        )
    return value


def validate_month(value: object) -> str:
    if not isinstance(value, str):
        raise ValidationError("월은 문자열이어야 합니다.", "YYYY-MM 형식의 연월을 입력해 주세요.")
    value = value.strip()
    try:
        parsed = datetime.strptime(value, "%Y-%m")
    except (TypeError, ValueError) as error:
        raise ValidationError(
            f"월 형식이 올바르지 않습니다: {value!r}",
            "YYYY-MM 형식의 실제 연월을 입력해 주세요.",
        ) from error
    if parsed.strftime("%Y-%m") != value:
        raise ValidationError(
            f"월 형식이 올바르지 않습니다: {value!r}",
            "YYYY-MM 형식으로 월을 두 자리로 입력해 주세요.",
        )
    return value


def validate_type(value: object) -> TransactionType:
    if not isinstance(value, str):
        raise ValidationError("거래 타입은 문자열이어야 합니다.", "income 또는 expense를 입력해 주세요.")
    normalized = value.strip().lower()
    if normalized not in {"income", "expense"}:
        raise ValidationError(
            f"허용되지 않는 거래 타입입니다: {value!r}",
            "income 또는 expense 중 하나를 입력해 주세요.",
        )
    return cast(TransactionType, normalized)


def validate_amount(value: int | str, field_name: str = "금액") -> int:
    if isinstance(value, bool):
        raise ValidationError(f"{field_name}은 양수 정수여야 합니다.", "1 이상의 정수를 입력해 주세요.")
    if not isinstance(value, (int, str)):
        raise ValidationError(
            f"{field_name}은 양수 정수여야 합니다: {value!r}",
            "소수나 쉼표 없이 1 이상의 정수를 입력해 주세요.",
        )
    try:
        amount = int(value)
    except (TypeError, ValueError) as error:
        raise ValidationError(
            f"{field_name}은 양수 정수여야 합니다: {value!r}",
            "쉼표 없이 1 이상의 정수를 입력해 주세요.",
        ) from error
    if isinstance(value, str) and str(amount) != value.strip():
        raise ValidationError(
            f"{field_name}은 양수 정수여야 합니다: {value!r}",
            "쉼표 없이 1 이상의 정수를 입력해 주세요.",
        )
    if amount <= 0:
        raise ValidationError(f"{field_name}은 0보다 커야 합니다.", "1 이상의 정수를 입력해 주세요.")
    return amount


def validate_name(value: object, field_name: str = "카테고리") -> str:
    if not isinstance(value, str):
        raise ValidationError(f"{field_name}는 문자열이어야 합니다.", f"{field_name} 이름을 입력해 주세요.")
    normalized = value.strip()
    if not normalized:
        raise ValidationError(f"{field_name}는 비어 있을 수 없습니다.", f"{field_name} 이름을 입력해 주세요.")
    if any(character in normalized for character in ("\n", "\r", "\t")):
        raise ValidationError(
            f"{field_name}에 줄바꿈이나 탭을 사용할 수 없습니다.",
            "한 줄의 이름을 입력해 주세요.",
        )
    return normalized


def parse_tags(value: str | Iterable[object] | None) -> tuple[str, ...]:
    if value is None:
        return ()
    if isinstance(value, str):
        candidates: Iterable[object] = value.split(",")
    elif isinstance(value, Iterable):
        candidates = value
    else:
        raise ValidationError("태그는 문자열 목록이어야 합니다.", "태그를 쉼표로 구분해 입력해 주세요.")
    result: list[str] = []
    seen: set[str] = set()
    for candidate in candidates:
        if not isinstance(candidate, str):
            raise ValidationError("각 태그는 문자열이어야 합니다.", "태그를 쉼표로 구분해 입력해 주세요.")
        tag = candidate.strip()
        if tag and tag not in seen:
            if any(character in tag for character in ("\n", "\r", "\t", ",")):
                raise ValidationError("태그 형식이 올바르지 않습니다.", "태그는 쉼표로 구분해 입력해 주세요.")
            result.append(tag)
            seen.add(tag)
    return tuple(result)
