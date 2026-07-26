"""argparse 기반 콘솔 사용자 인터페이스."""

from __future__ import annotations

import argparse
from collections.abc import Callable, Iterable, Sequence
import logging
import sys
from typing import TypeVar

from .decorators import configure_file_logging, log_execution
from .errors import AppError, StorageError, ValidationError
from .models import MonthlySummary, SearchCriteria, Transaction
from .services import LedgerService
from .validators import (
    parse_tags,
    validate_amount,
    validate_date,
    validate_name,
    validate_path,
    validate_type,
)

T = TypeVar("T")
LOGGER = logging.getLogger("budget_app")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="python -m budget_app",
        description="JSONL 파일 기반 콘솔 가계부",
    )
    parser.add_argument(
        "--data-dir",
        default="data",
        metavar="PATH",
        help="저장 폴더 (기본값: ./data, 명령어 앞에 지정)",
    )
    commands = parser.add_subparsers(dest="command", required=True)

    commands.add_parser("add", help="거래를 대화형으로 추가")

    list_parser = commands.add_parser("list", help="최신 거래 목록 조회")
    list_parser.add_argument(
        "--limit", type=int, default=20, help="출력할 최대 건수 (기본값: 20, 0은 전체)"
    )

    search = commands.add_parser("search", help="조건으로 거래 검색")
    search.add_argument("--from", dest="date_from", metavar="YYYY-MM-DD")
    search.add_argument("--to", dest="date_to", metavar="YYYY-MM-DD")
    search.add_argument("--category")
    search.add_argument("--type", choices=("income", "expense"))
    search.add_argument("--q", help="메모 키워드")
    search.add_argument("--tag")

    summary = commands.add_parser("summary", help="월별 수입·지출 요약")
    summary.add_argument("--month", required=True, metavar="YYYY-MM")
    summary.add_argument("--top", type=int, default=3, help="지출 카테고리 상위 개수")

    budget = commands.add_parser("budget", help="월 예산 설정·조회")
    budget_commands = budget.add_subparsers(dest="budget_command", required=True)
    budget_set = budget_commands.add_parser("set", help="월 예산 설정")
    budget_set.add_argument("--month", required=True, metavar="YYYY-MM")
    budget_set.add_argument("--amount", required=True)
    budget_get = budget_commands.add_parser("get", help="월 예산 조회")
    budget_get.add_argument("--month", required=True, metavar="YYYY-MM")
    budget_commands.add_parser("list", help="전체 월 예산 조회")

    category = commands.add_parser("category", help="카테고리 관리")
    category_commands = category.add_subparsers(dest="category_command", required=True)
    category_add = category_commands.add_parser("add", help="카테고리 추가")
    category_add.add_argument("--name", required=True)
    category_commands.add_parser("list", help="카테고리 목록")
    category_remove = category_commands.add_parser("remove", help="카테고리 삭제")
    category_remove.add_argument("--name", required=True)

    update = commands.add_parser("update", help="옵션 방식으로 거래 수정")
    update.add_argument("--id", required=True)
    update.add_argument("--date")
    update.add_argument("--type", choices=("income", "expense"))
    update.add_argument("--category")
    update.add_argument("--amount")
    update.add_argument("--memo")
    update.add_argument("--tags", help="쉼표로 구분, 빈 문자열이면 태그 삭제")

    delete = commands.add_parser("delete", help="id로 거래 삭제")
    delete.add_argument("--id", required=True)

    import_parser = commands.add_parser("import", help="고정 스키마 CSV 가져오기")
    import_parser.add_argument("--from", dest="source", required=True, metavar="CSV")

    export = commands.add_parser("export", help="조건에 맞는 거래를 CSV로 내보내기")
    export.add_argument("--out", required=True, metavar="CSV")
    export.add_argument("--month", metavar="YYYY-MM")
    export.add_argument("--from", dest="date_from", metavar="YYYY-MM-DD")
    export.add_argument("--to", dest="date_to", metavar="YYYY-MM-DD")
    return parser


@log_execution
def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        data_dir = validate_path(args.data_dir, "저장 폴더 경로")
        configure_file_logging(data_dir / "budget_app.log")
        service = LedgerService(data_dir)
        return _dispatch(service, args)
    except BrokenPipeError:
        LOGGER.info("output pipe closed by consumer")
        return 0
    except AppError as error:
        _print_error(error)
        return 1
    except (EOFError, KeyboardInterrupt):
        _print_error(AppError("입력이 중단되었습니다.", "명령을 다시 실행해 입력을 완료해 주세요."))
        return 130
    except Exception as error:  # 최상위 경계에서만 예상 밖 오류를 사용자 메시지로 변환한다.
        LOGGER.exception("unexpected CLI failure")
        _print_error(
            StorageError(
                f"명령을 처리하지 못했습니다: {error}",
                "입력값과 저장 파일 상태를 확인한 뒤 다시 시도해 주세요.",
            )
        )
        return 1


def _dispatch(service: LedgerService, args: argparse.Namespace) -> int:
    """파싱된 하위 명령을 알맞은 서비스 호출로 연결하고 결과를 출력한다."""

    if args.command == "add":
        return _add_interactively(service)
    if args.command == "list":
        _print_transactions(service.list_transactions(args.limit))
    elif args.command == "search":
        criteria = SearchCriteria(
            date_from=args.date_from,
            date_to=args.date_to,
            category=args.category,
            type=args.type,
            query=args.q,
            tag=args.tag,
        )
        _print_transactions(service.search_transactions(criteria))
    elif args.command == "summary":
        _print_summary(service.monthly_summary(args.month, args.top))
    elif args.command == "budget":
        _handle_budget(service, args)
    elif args.command == "category":
        _handle_category(service, args)
    elif args.command == "update":
        _handle_update(service, args)
    elif args.command == "delete":
        service.delete_transaction(args.id)
        print(f"삭제 완료 - id: {_display_text(args.id)}")
    elif args.command == "import":
        count = service.import_csv(args.source)
        print(f"가져오기 완료: {count}건")
    elif args.command == "export":
        count = service.export_csv(
            args.out,
            month=args.month,
            date_from=args.date_from,
            date_to=args.date_to,
        )
        print(f"내보내기 완료: {count}건 - {_display_text(args.out)}")
    return 0


def _add_interactively(service: LedgerService) -> int:
    """거래에 필요한 값을 한 항목씩 대화형으로 입력받아 한 건을 저장한다."""

    date = _prompt("날짜 (YYYY-MM-DD): ", validate_date)
    transaction_type = _prompt("타입 (income/expense): ", validate_type)
    categories = service.list_categories()
    print(f"등록 카테고리: {', '.join(_display_text(item) for item in categories)}")

    def registered_category(value: str) -> str:
        """입력한 카테고리가 등록된 것인지 확인하는 프롬프트용 파서."""

        category = validate_name(value)
        if category not in service.list_categories():
            raise ValidationError(
                f"등록되지 않은 카테고리입니다: {category!r}",
                "위 목록에서 선택하거나 category add로 먼저 등록해 주세요.",
            )
        return category

    category = _prompt("카테고리: ", registered_category)
    amount = _prompt("금액 (양수 정수): ", validate_amount)
    memo = input("메모 (선택): ").strip()
    tags = _prompt("태그 (쉼표 구분, 선택): ", parse_tags)
    transaction = service.add_transaction(
        date=date,
        type=transaction_type,
        category=category,
        amount=amount,
        memo=memo,
        tags=tags,
    )
    print(f"저장 완료 - id: {_display_text(transaction.id)}")
    return 0


def _prompt(prompt: str, parser: Callable[[str], T]) -> T:
    """검증에 통과할 때까지 다시 물어보며, 통과한 값을 파싱해 돌려준다."""

    while True:
        raw_value = input(prompt)
        try:
            return parser(raw_value)
        except ValidationError as error:
            print(
                f"입력 오류: {_display_text(str(error))} ({_display_text(error.hint)})",
                file=sys.stderr,
            )


def _handle_update(service: LedgerService, args: argparse.Namespace) -> None:
    """지정된(None이 아닌) 옵션만 모아 수정 요청으로 넘긴다."""

    updates = {
        key: value
        for key, value in {
            "date": args.date,
            "type": args.type,
            "category": args.category,
            "amount": args.amount,
            "memo": args.memo,
            "tags": parse_tags(args.tags) if args.tags is not None else None,
        }.items()
        if value is not None
    }
    transaction = service.update_transaction(args.id, updates)
    print(f"수정 완료 - id: {_display_text(transaction.id)}")


def _handle_budget(service: LedgerService, args: argparse.Namespace) -> None:
    """budget 하위 명령(set/get/list)을 분기해 예산을 설정·조회한다."""

    if args.budget_command == "set":
        service.set_budget(args.month, args.amount)
        print(f"예산 저장 완료 - {args.month}: {_money(validate_amount(args.amount))}")
    elif args.budget_command == "get":
        budget = service.get_budget(args.month)
        if budget is None:
            print(f"{args.month}: 설정된 예산 없음")
        else:
            print(f"{args.month}: {_money(budget)}")
    else:
        budgets = service.list_budgets()
        if not budgets:
            print("설정된 예산 없음")
        for month, amount in sorted(budgets.items()):
            print(f"{month}: {_money(amount)}")


def _handle_category(service: LedgerService, args: argparse.Namespace) -> None:
    """category 하위 명령(add/remove/list)을 분기해 카테고리를 관리한다."""

    if args.category_command == "add":
        if service.add_category(args.name):
            print(f"카테고리 추가 완료: {_display_text(args.name.strip())}")
        else:
            print(f"이미 등록된 카테고리: {_display_text(args.name.strip())}")
    elif args.category_command == "remove":
        if service.remove_category(args.name):
            print(f"카테고리 삭제 완료: {_display_text(args.name.strip())}")
        else:
            print(f"없는 카테고리: {_display_text(args.name.strip())}")
    else:
        for category in service.list_categories():
            print(_display_text(category))


def _print_transactions(transactions: Iterable[Transaction]) -> None:
    """거래들을 ` | `로 구분된 한 줄씩 출력하고, 없으면 안내 문구를 낸다."""

    count = 0
    for transaction in transactions:
        transaction_id = _display_text(transaction.id)
        date = _display_text(transaction.date)
        transaction_type = _display_text(transaction.type)
        category = _display_text(transaction.category)
        tags = _display_text(",".join(transaction.tags)) or "-"
        memo = _display_text(transaction.memo) or "-"
        print(
            f"{transaction_id} | {date} | {transaction_type:<7} | "
            f"{category} | {_money(transaction.amount)} | {memo} | {tags}"
        )
        count += 1
    if count == 0:
        print("거래 데이터 없음")


def _print_summary(summary: MonthlySummary) -> None:
    """월 요약(수입·지출·잔액, 지출 TOP, 예산 사용률·초과)을 출력한다."""

    if not summary.has_transactions:
        print(f"{summary.month}: 데이터 없음")
    print(f"총 수입: {_money(summary.total_income)}")
    print(f"총 지출: {_money(summary.total_expense)}")
    print(f"잔액: {_money(summary.balance)}")
    if summary.category_expenses:
        print("카테고리별 지출 TOP")
        for rank, (category, amount) in enumerate(summary.category_expenses, start=1):
            print(f"  {rank}. {_display_text(category)}: {_money(amount)}")
    if summary.budget is not None:
        print(f"예산: {_money(summary.budget)}")
        print(f"예산 사용률: {summary.budget_usage_percent:.1f}%")
        if summary.is_budget_exceeded:
            print(f"예산 초과 경고: {_money(summary.total_expense - summary.budget)} 초과")


def _money(amount: int) -> str:
    """정수 금액을 천 단위 쉼표로 끊어 문자열로 만든다(임의 자릿수 지원)."""

    sign = "-" if amount < 0 else ""
    remaining = abs(amount)

    groups: list[int] = []
    while remaining >= 1000:
        remaining, group = divmod(remaining, 1000)
        groups.append(group)
    suffix = "".join(f",{group:03d}" for group in reversed(groups))
    return f"{sign}{remaining}{suffix}"


def _display_text(value: str) -> str:
    """콘솔 한 줄과 ` | ` 구분 구조를 깨는 문자를 가시적으로 이스케이프한다."""

    escaped: list[str] = []
    for character in value:
        if character == "\\":
            escaped.append("\\\\")
        elif character == "|":
            escaped.append("\\u007c")
        elif character.isprintable():
            escaped.append(character)
        else:
            escaped.append(character.encode("unicode_escape").decode("ascii"))
    return "".join(escaped)


def _print_error(error: AppError) -> None:
    print(f"오류: {_display_text(str(error))}", file=sys.stderr)
    print(f"해결 방법: {_display_text(error.hint)}", file=sys.stderr)
