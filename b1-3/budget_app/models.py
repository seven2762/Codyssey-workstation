"""가계부의 타입 계약과 불변 데이터 모델."""

from __future__ import annotations

from dataclasses import asdict, dataclass
from typing import Any, cast

from .errors import ValidationError
from .validators import (
    TransactionType,
    parse_tags,
    validate_amount,
    validate_date,
    validate_month,
    validate_name,
    validate_type,
)


@dataclass(frozen=True, slots=True)
class Transaction:
    id: str
    date: str
    type: TransactionType
    category: str
    amount: int
    memo: str = ""
    tags: tuple[str, ...] = ()

    @classmethod
    def create(
        cls,
        transaction_id: str,
        date: str,
        type: str,
        category: str,
        amount: int | str,
        memo: str = "",
        tags: str | tuple[str, ...] | list[str] | None = None,
    ) -> Transaction:
        if not isinstance(transaction_id, str):
            raise ValidationError("거래 id는 문자열이어야 합니다.", "유효한 거래 id를 지정해 주세요.")
        identifier = transaction_id.strip()
        if not identifier:
            raise ValidationError("거래 id는 비어 있을 수 없습니다.", "유효한 거래 id를 지정해 주세요.")
        return cls(
            id=identifier,
            date=validate_date(date),
            type=validate_type(type),
            category=validate_name(category),
            amount=validate_amount(amount),
            memo=validate_memo(memo),
            tags=parse_tags(tags),
        )

    @classmethod
    def from_dict(cls, record: dict[str, Any]) -> Transaction:
        try:
            return cls.create(
                transaction_id=record["id"],
                date=record["date"],
                type=record["type"],
                category=record["category"],
                amount=record["amount"],
                memo=record.get("memo", ""),
                tags=record.get("tags", ()),
            )
        except KeyError as error:
            raise ValidationError(
                f"거래 데이터에 필수 필드가 없습니다: {error.args[0]}",
                "손상된 거래 파일을 백업본으로 복구해 주세요.",
            ) from error

    def to_dict(self) -> dict[str, Any]:
        record = asdict(self)
        record["tags"] = list(self.tags)
        return record

    def with_updates(self, updates: dict[str, object]) -> Transaction:
        allowed = {"date", "type", "category", "amount", "memo", "tags"}
        unknown = set(updates) - allowed
        if unknown:
            raise ValidationError(f"수정할 수 없는 필드입니다: {', '.join(sorted(unknown))}")
        values = self.to_dict()
        values.update(updates)
        return Transaction.create(
            transaction_id=self.id,
            date=cast(str, values["date"]),
            type=cast(str, values["type"]),
            category=cast(str, values["category"]),
            amount=values["amount"],  # type: ignore[arg-type]
            memo=str(values.get("memo", "")),
            tags=values.get("tags"),  # type: ignore[arg-type]
        )


@dataclass(frozen=True, slots=True)
class SearchCriteria:
    date_from: str | None = None
    date_to: str | None = None
    category: str | None = None
    type: str | None = None
    query: str | None = None
    tag: str | None = None

    def __post_init__(self) -> None:
        if self.date_from is not None:
            object.__setattr__(self, "date_from", validate_date(self.date_from, "시작일"))
        if self.date_to is not None:
            object.__setattr__(self, "date_to", validate_date(self.date_to, "종료일"))
        if self.date_from and self.date_to and self.date_from > self.date_to:
            raise ValidationError("시작일이 종료일보다 늦습니다.", "--from을 --to보다 이른 날짜로 지정해 주세요.")
        if self.category is not None:
            object.__setattr__(self, "category", validate_name(self.category))
        if self.type is not None:
            object.__setattr__(self, "type", validate_type(self.type))
        if self.query is not None:
            if not isinstance(self.query, str):
                raise ValidationError("검색어는 문자열이어야 합니다.")
            query = self.query.strip()
            if not query:
                raise ValidationError("검색어는 비어 있을 수 없습니다.", "--q에 검색할 메모 내용을 입력해 주세요.")
            object.__setattr__(self, "query", query)
        if self.tag is not None:
            if not isinstance(self.tag, str):
                raise ValidationError("검색 태그는 문자열이어야 합니다.")
            tag = self.tag.strip()
            if not tag:
                raise ValidationError("검색 태그는 비어 있을 수 없습니다.")
            object.__setattr__(self, "tag", tag)

    def matches(self, transaction: Transaction) -> bool:
        return not (
            (self.date_from and transaction.date < self.date_from)
            or (self.date_to and transaction.date > self.date_to)
            or (self.category and transaction.category != self.category)
            or (self.type and transaction.type != self.type)
            or (self.query and self.query.casefold() not in transaction.memo.casefold())
            or (self.tag and self.tag not in transaction.tags)
        )


@dataclass(frozen=True, slots=True)
class MonthlySummary:
    month: str
    total_income: int
    total_expense: int
    category_expenses: tuple[tuple[str, int], ...]
    transaction_count: int
    budget: int | None = None

    def __post_init__(self) -> None:
        validate_month(self.month)

    @property
    def balance(self) -> int:
        return self.total_income - self.total_expense

    @property
    def has_transactions(self) -> bool:
        return self.transaction_count > 0

    @property
    def budget_usage_percent(self) -> float | None:
        if self.budget is None:
            return None
        return self.total_expense / self.budget * 100

    @property
    def is_budget_exceeded(self) -> bool:
        return self.budget is not None and self.total_expense > self.budget


def validate_memo(value: object) -> str:
    if not isinstance(value, str):
        raise ValidationError("메모는 문자열이어야 합니다.", "메모를 문자열로 입력하거나 비워 주세요.")
    return value.strip()
