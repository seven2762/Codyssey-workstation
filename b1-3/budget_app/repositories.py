"""JSONL 저장소와 원자적 파일 재작성 구현."""

from __future__ import annotations

from collections.abc import Iterable, Iterator
import json
import logging
import os
from pathlib import Path
import tempfile
from typing import Any

from .errors import StorageError, ValidationError
from .models import Transaction
from .validators import validate_amount, validate_month, validate_name

DEFAULT_CATEGORIES = ("food", "transport", "housing", "salary", "health", "education", "etc")
LOGGER = logging.getLogger("budget_app")


def _encode_record(record: dict[str, Any]) -> str:
    return json.dumps(record, ensure_ascii=False, separators=(",", ":")) + "\n"


def _reverse_lines(path: Path, chunk_size: int = 8192) -> Iterator[str]:
    """파일 전체를 메모리에 올리지 않고 마지막 줄부터 생성한다."""

    with path.open("rb") as file:
        file.seek(0, os.SEEK_END)
        position = file.tell()
        buffer = b""
        while position > 0:
            read_size = min(chunk_size, position)
            position -= read_size
            file.seek(position)
            buffer = file.read(read_size) + buffer
            lines = buffer.split(b"\n")
            buffer = lines[0]
            for line in reversed(lines[1:]):
                if line.strip():
                    yield line.decode("utf-8")
        if buffer.strip():
            yield buffer.decode("utf-8")


def _json_records(path: Path, *, reverse: bool = False) -> Iterator[dict[str, Any]]:
    try:
        lines: Iterable[str]
        if reverse:
            lines = _reverse_lines(path)
        else:
            lines = path.open("r", encoding="utf-8")
        with lines if hasattr(lines, "__enter__") else _null_context(lines) as source:
            for line_number, line in enumerate(source, start=1):
                if not line.strip():
                    continue
                try:
                    record = json.loads(line)
                except json.JSONDecodeError as error:
                    raise StorageError(
                        f"{path.name}의 JSONL 데이터가 손상되었습니다(읽기 순서 {line_number}번째 줄).",
                        "파일을 백업본으로 복구하거나 손상된 줄을 올바른 JSON 객체로 수정해 주세요.",
                    ) from error
                if not isinstance(record, dict):
                    raise StorageError(
                        f"{path.name}에 JSON 객체가 아닌 데이터가 있습니다.",
                        "각 줄을 하나의 JSON 객체로 수정해 주세요.",
                    )
                yield record
    except (OSError, UnicodeError) as error:
        raise StorageError(
            f"{path.name} 파일을 읽을 수 없습니다: {error}",
            "파일 경로, UTF-8 인코딩, 읽기 권한을 확인해 주세요.",
        ) from error


class _null_context:
    """이미 열린 컨텍스트가 아닌 이터레이터를 with 문에서 사용한다."""

    def __init__(self, value: Iterable[str]) -> None:
        self.value = value

    def __enter__(self) -> Iterable[str]:
        return self.value

    def __exit__(self, *_: object) -> None:
        return None


def _atomic_write(path: Path, records: Iterable[dict[str, Any]]) -> None:
    temporary_path: Path | None = None
    try:
        descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=path.parent)
        temporary_path = Path(temporary_name)
        with os.fdopen(descriptor, "w", encoding="utf-8", newline="\n") as file:
            for record in records:
                file.write(_encode_record(record))
            file.flush()
            os.fsync(file.fileno())
        os.replace(temporary_path, path)
    except OSError as error:
        raise StorageError(
            f"{path.name} 파일을 안전하게 저장할 수 없습니다: {error}",
            "저장 폴더의 쓰기 권한과 남은 디스크 공간을 확인해 주세요.",
        ) from error
    finally:
        if temporary_path is not None:
            try:
                temporary_path.unlink(missing_ok=True)
            except OSError as cleanup_error:
                LOGGER.warning("temporary file cleanup failed: %s", cleanup_error)


class TransactionRepository:
    """추가에는 append, 수정/삭제에는 원자적 전체 재작성을 사용한다."""

    def __init__(self, data_dir: Path) -> None:
        self.data_dir = Path(data_dir)
        self.path = self.data_dir / "transactions.jsonl"
        try:
            self.data_dir.mkdir(parents=True, exist_ok=True)
            self.path.touch(exist_ok=True)
        except OSError as error:
            raise StorageError(f"거래 저장 파일을 초기화할 수 없습니다: {error}") from error

    def add(self, transaction: Transaction) -> None:
        try:
            with self.path.open("a", encoding="utf-8", newline="\n") as file:
                file.write(_encode_record(transaction.to_dict()))
                file.flush()
                os.fsync(file.fileno())
        except OSError as error:
            raise StorageError(
                f"거래를 저장할 수 없습니다: {error}",
                "저장 폴더의 쓰기 권한과 남은 디스크 공간을 확인해 주세요.",
            ) from error

    def add_many_atomic(self, transactions: Iterable[Transaction]) -> None:
        def combined_records() -> Iterator[dict[str, Any]]:
            yield from _json_records(self.path)
            for transaction in transactions:
                yield transaction.to_dict()

        _atomic_write(self.path, combined_records())

    def iter_transactions(self, *, latest_first: bool = True) -> Iterator[Transaction]:
        for record in _json_records(self.path, reverse=latest_first):
            try:
                yield Transaction.from_dict(record)
            except ValidationError as error:
                raise StorageError(
                    f"{self.path.name}에 유효하지 않은 거래가 있습니다: {error}",
                    "문제가 있는 JSONL 줄을 수정하거나 백업본으로 복구해 주세요.",
                ) from error

    def get(self, transaction_id: str) -> Transaction | None:
        return next(
            (transaction for transaction in self.iter_transactions() if transaction.id == transaction_id),
            None,
        )

    def update(self, transaction_id: str, updates: dict[str, object]) -> Transaction | None:
        found: Transaction | None = None

        def updated_records() -> Iterator[dict[str, Any]]:
            nonlocal found
            for transaction in self.iter_transactions(latest_first=False):
                if transaction.id == transaction_id:
                    found = transaction.with_updates(updates)
                    yield found.to_dict()
                else:
                    yield transaction.to_dict()

        _atomic_write(self.path, updated_records())
        return found

    def delete(self, transaction_id: str) -> bool:
        found = False

        def remaining_records() -> Iterator[dict[str, Any]]:
            nonlocal found
            for transaction in self.iter_transactions(latest_first=False):
                if transaction.id == transaction_id:
                    found = True
                    continue
                yield transaction.to_dict()

        _atomic_write(self.path, remaining_records())
        return found

    def uses_category(self, category: str) -> bool:
        return any(transaction.category == category for transaction in self.iter_transactions())


class CategoryStore:
    """작고 자주 조회되는 카테고리 집합을 JSONL로 관리한다."""

    def __init__(self, data_dir: Path) -> None:
        self.data_dir = Path(data_dir)
        self.path = self.data_dir / "categories.jsonl"
        try:
            self.data_dir.mkdir(parents=True, exist_ok=True)
            if not self.path.exists() or self.path.stat().st_size == 0:
                _atomic_write(self.path, ({"name": name} for name in DEFAULT_CATEGORIES))
        except OSError as error:
            raise StorageError(f"카테고리 저장 파일을 초기화할 수 없습니다: {error}") from error

    def list(self) -> list[str]:
        categories: list[str] = []
        for record in _json_records(self.path):
            try:
                categories.append(validate_name(record["name"]))
            except (KeyError, ValidationError) as error:
                raise StorageError(
                    f"{self.path.name}에 유효하지 않은 카테고리가 있습니다.",
                    "각 줄을 {\"name\": \"카테고리\"} 형식으로 수정해 주세요.",
                ) from error
        return categories

    def contains(self, category: str) -> bool:
        return category in self.list()

    def add(self, category: str) -> bool:
        category = validate_name(category)
        categories = self.list()
        if category in categories:
            return False
        categories.append(category)
        _atomic_write(self.path, ({"name": name} for name in categories))
        return True

    def remove(self, category: str) -> bool:
        category = validate_name(category)
        categories = self.list()
        if category not in categories:
            return False
        _atomic_write(self.path, ({"name": name} for name in categories if name != category))
        return True


class BudgetStore:
    """월별 예산을 한 달에 한 레코드로 저장한다."""

    def __init__(self, data_dir: Path) -> None:
        self.data_dir = Path(data_dir)
        self.path = self.data_dir / "budgets.jsonl"
        try:
            self.data_dir.mkdir(parents=True, exist_ok=True)
            self.path.touch(exist_ok=True)
        except OSError as error:
            raise StorageError(f"예산 저장 파일을 초기화할 수 없습니다: {error}") from error

    def list(self) -> dict[str, int]:
        budgets: dict[str, int] = {}
        for record in _json_records(self.path):
            try:
                month = validate_month(record["month"])
                amount = validate_amount(record["amount"], "예산")
            except (KeyError, ValidationError) as error:
                raise StorageError(
                    f"{self.path.name}에 유효하지 않은 예산이 있습니다.",
                    "각 줄의 month와 amount 값을 확인해 주세요.",
                ) from error
            budgets[month] = amount
        return budgets

    def get(self, month: str) -> int | None:
        month = validate_month(month)
        return self.list().get(month)

    def set(self, month: str, amount: int | str) -> None:
        month = validate_month(month)
        normalized_amount = validate_amount(amount, "예산")
        budgets = self.list()
        budgets[month] = normalized_amount
        _atomic_write(
            self.path,
            ({"month": key, "amount": value} for key, value in sorted(budgets.items())),
        )
