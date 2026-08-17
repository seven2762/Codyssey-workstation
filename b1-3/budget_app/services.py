"""저장소를 조합해 가계부 사용 사례를 제공한다."""

from __future__ import annotations

from collections import defaultdict
from collections.abc import Iterator
import csv
from itertools import islice
import logging
import os
from pathlib import Path
import tempfile
from uuid import uuid4

from .decorators import log_execution
from .errors import ConflictError, NotFoundError, StorageError, ValidationError
from .models import MonthlySummary, SearchCriteria, Transaction
from .repositories import BudgetStore, CategoryStore, TransactionRepository
from .validators import parse_tags, validate_amount, validate_month, validate_name, validate_path

# import 시 반드시 있어야 하는 데이터 열. `id`는 선택이며 있으면 upsert 키로 쓴다.
CSV_DATA_COLUMNS = ("date", "type", "category", "amount", "memo", "tags")
# export가 쓰는 전체 열 순서. `id`를 함께 내보내 재가져오기가 멱등이 되도록 한다.
CSV_COLUMNS = ("id", *CSV_DATA_COLUMNS)
LOGGER = logging.getLogger("budget_app")


class LedgerService:
    """CLI와 파일 저장소 사이의 정책 및 유스케이스 계층."""

    def __init__(self, data_dir: Path | str = Path("data")) -> None:
        directory = validate_path(data_dir, "저장 폴더 경로")
        self.transactions = TransactionRepository(directory)
        self.categories = CategoryStore(directory)
        self.budgets = BudgetStore(directory)

    @log_execution
    def add_transaction(
        self,
        *,
        date: str,
        type: str,
        category: str,
        amount: int | str,
        memo: str = "",
        tags: str | tuple[str, ...] | list[str] | None = None,
    ) -> Transaction:
        category = validate_name(category)
        self._require_category(category)
        transaction = Transaction.create(
            transaction_id=uuid4().hex,
            date=date,
            type=type,
            category=category,
            amount=amount,
            memo=memo,
            tags=tags,
        )
        self.transactions.add(transaction)
        return transaction

    def list_transactions(self, limit: int = 20) -> list[Transaction]:
        if isinstance(limit, bool) or limit < 0:
            raise ValidationError(
                "--limit은 0 이상의 정수여야 합니다.",
                "전체를 보려면 0을, 개수를 제한하려면 1 이상을 지정해 주세요.",
            )
        transactions = self.transactions.iter_transactions()
        if limit == 0:
            return list(transactions)
        return list(islice(transactions, limit))

    def search_transactions(self, criteria: SearchCriteria) -> Iterator[Transaction]:
        return (
            transaction
            for transaction in self.transactions.iter_transactions()
            if criteria.matches(transaction)
        )

    @log_execution
    def update_transaction(self, transaction_id: str, updates: dict[str, object]) -> Transaction:
        transaction_id = validate_name(transaction_id, "거래 id")
        if not updates:
            raise ValidationError("수정할 필드가 없습니다.", "하나 이상의 수정 옵션을 지정해 주세요.")
        if "category" in updates:
            category = validate_name(updates["category"])
            self._require_category(category)
            updates = {**updates, "category": category}
        updated = self.transactions.update(transaction_id, updates)
        if updated is None:
            raise NotFoundError(
                f"거래 id {transaction_id!r}를 찾을 수 없습니다.",
                "list 또는 search로 올바른 id를 확인해 주세요.",
            )
        return updated

    @log_execution
    def delete_transaction(self, transaction_id: str) -> None:
        transaction_id = validate_name(transaction_id, "거래 id")
        if not self.transactions.delete(transaction_id):
            raise NotFoundError(
                f"거래 id {transaction_id!r}를 찾을 수 없습니다.",
                "list 또는 search로 올바른 id를 확인해 주세요.",
            )

    def monthly_summary(self, month: str, top: int = 3) -> MonthlySummary:
        month = validate_month(month)
        if isinstance(top, bool) or top <= 0:
            raise ValidationError("--top은 1 이상의 정수여야 합니다.")
        income = 0
        expense = 0
        count = 0
        category_expenses: defaultdict[str, int] = defaultdict(int)
        for transaction in self.transactions.iter_transactions(latest_first=False):
            if not transaction.date.startswith(f"{month}-"):
                continue
            count += 1
            if transaction.type == "income":
                income += transaction.amount
            else:
                expense += transaction.amount
                category_expenses[transaction.category] += transaction.amount
        ranked = tuple(sorted(category_expenses.items(), key=lambda item: (-item[1], item[0]))[:top])
        return MonthlySummary(
            month=month,
            total_income=income,
            total_expense=expense,
            category_expenses=ranked,
            transaction_count=count,
            budget=self.budgets.get(month),
        )

    @log_execution
    def set_budget(self, month: str, amount: int | str) -> None:
        self.budgets.set(month, amount)

    def get_budget(self, month: str) -> int | None:
        return self.budgets.get(month)

    def list_budgets(self) -> dict[str, int]:
        return self.budgets.list()

    @log_execution
    def add_category(self, category: str) -> bool:
        return self.categories.add(category)

    def list_categories(self) -> list[str]:
        return self.categories.list()

    @log_execution
    def remove_category(self, category: str) -> bool:
        category = validate_name(category)
        if self.transactions.uses_category(category):
            raise ConflictError(
                f"카테고리 {category!r}를 사용하는 거래가 있어 삭제할 수 없습니다.",
                "해당 거래의 카테고리를 먼저 수정한 뒤 다시 삭제해 주세요.",
            )
        return self.categories.remove(category)

    @log_execution
    def import_csv(self, source: Path | str) -> int:
        source_path = validate_path(source, "가져오기 CSV 경로")
        try:
            with source_path.open("r", encoding="utf-8-sig", newline="") as source_file:
                reader = csv.DictReader(source_file)
                missing = set(CSV_DATA_COLUMNS) - set(reader.fieldnames or ())
                if missing:
                    raise ValidationError(
                        f"CSV 헤더에 필수 열이 없습니다: {', '.join(sorted(missing))}",
                        f"헤더를 {','.join(CSV_DATA_COLUMNS)} 순서로 작성해 주세요.",
                    )
                rows = list(reader)

            transactions: list[Transaction] = []
            for row_number, row in enumerate(rows, start=2):
                try:
                    transactions.append(self._transaction_from_csv_row(row))
                except ValidationError as error:
                    raise ValidationError(
                        f"CSV {row_number}행이 올바르지 않습니다: {error}",
                        error.hint,
                    ) from error

            # id가 있으면 같은 id 거래를 교체(upsert)하고, 없으면 새 거래로 추가한다.
            self.transactions.upsert_many_atomic(transactions)
        except (ValidationError, StorageError):
            raise
        except (OSError, UnicodeError, csv.Error) as error:
            raise StorageError(
                f"CSV 파일을 가져올 수 없습니다: {error}",
                "파일 경로, 읽기 권한, UTF-8 인코딩과 CSV 형식을 확인해 주세요.",
            ) from error
        return len(transactions)

    @log_execution
    def export_csv(
        self,
        destination: Path | str,
        *,
        month: str | None = None,
        date_from: str | None = None,
        date_to: str | None = None,
    ) -> int:
        has_month = month is not None
        has_from = date_from is not None
        has_to = date_to is not None
        if has_month and (has_from or has_to):
            raise ValidationError(
                "--month와 기간 조건을 함께 사용할 수 없습니다.",
                "--month 또는 --from/--to 중 한 방식을 선택해 주세요.",
            )
        if has_month:
            month = validate_month(month)
        elif not has_from and not has_to:
            raise ValidationError(
                "내보내기 조건이 없습니다.",
                "--month 또는 --from과 --to를 지정해 주세요.",
            )
        elif not has_from or not has_to:
            raise ValidationError(
                "기간 내보내기에는 --from과 --to가 모두 필요합니다.",
                "시작일과 종료일을 함께 지정해 주세요.",
            )

        criteria = None if month is not None else SearchCriteria(date_from=date_from, date_to=date_to)

        destination_path = validate_path(destination, "내보내기 CSV 경로")
        temporary_path: Path | None = None
        count = 0
        try:
            destination_path.parent.mkdir(parents=True, exist_ok=True)
            descriptor, temporary_name = tempfile.mkstemp(
                prefix=f".{destination_path.name}.", suffix=".tmp", dir=destination_path.parent
            )
            temporary_path = Path(temporary_name)
            with os.fdopen(descriptor, "w", encoding="utf-8", newline="") as file:
                writer = csv.DictWriter(file, fieldnames=CSV_COLUMNS)
                writer.writeheader()
                for transaction in self.transactions.iter_transactions():
                    if month:
                        if not transaction.date.startswith(f"{month}-"):
                            continue
                    elif criteria is not None and not criteria.matches(transaction):
                        continue
                    writer.writerow(
                        {
                            "id": transaction.id,
                            "date": transaction.date,
                            "type": transaction.type,
                            "category": transaction.category,
                            "amount": transaction.amount,
                            "memo": transaction.memo,
                            "tags": ",".join(transaction.tags),
                        }
                    )
                    count += 1
                file.flush()
                os.fsync(file.fileno())
            os.replace(temporary_path, destination_path)
        except (OSError, csv.Error) as error:
            raise StorageError(
                f"CSV 파일을 내보낼 수 없습니다: {error}",
                "출력 경로의 쓰기 권한과 남은 디스크 공간을 확인해 주세요.",
            ) from error
        finally:
            if temporary_path is not None:
                try:
                    temporary_path.unlink(missing_ok=True)
                except OSError as cleanup_error:
                    LOGGER.warning("CSV temporary file cleanup failed: %s", cleanup_error)
        return count

    def _require_category(self, category: str) -> None:
        if not self.categories.contains(category):
            raise ValidationError(
                f"등록되지 않은 카테고리입니다: {category!r}",
                "category list로 확인하거나 category add로 먼저 등록해 주세요.",
            )

    def _transaction_from_csv_row(self, row: dict[str, str | None]) -> Transaction:
        category = validate_name(row.get("category") or "")
        self._require_category(category)
        raw_id = (row.get("id") or "").strip()
        transaction_id = validate_name(raw_id, "거래 id") if raw_id else uuid4().hex
        return Transaction.create(
            transaction_id=transaction_id,
            date=row.get("date") or "",
            type=row.get("type") or "",
            category=category,
            amount=row.get("amount") or "",
            memo=row.get("memo") or "",
            tags=parse_tags(row.get("tags")),
        )
