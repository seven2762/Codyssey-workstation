"""실행 로그와 시간 측정을 비즈니스 로직에서 분리한다."""

from __future__ import annotations

from collections.abc import Callable
from functools import wraps
import logging
from pathlib import Path
from time import perf_counter
from typing import ParamSpec, TypeVar

P = ParamSpec("P")
R = TypeVar("R")
LOGGER = logging.getLogger("budget_app")
LOGGER.addHandler(logging.NullHandler())
LOGGER.propagate = False


def log_execution(function: Callable[P, R]) -> Callable[P, R]:
    """호출 성공/실패와 실행 시간을 로깅하고 원래 예외는 보존한다."""

    @wraps(function)
    def wrapper(*args: P.args, **kwargs: P.kwargs) -> R:
        started_at = perf_counter()
        try:
            result = function(*args, **kwargs)
        except Exception:
            elapsed = (perf_counter() - started_at) * 1000
            LOGGER.exception("%s failed in %.2f ms", function.__name__, elapsed)
            raise
        elapsed = (perf_counter() - started_at) * 1000
        LOGGER.info("%s completed in %.2f ms", function.__name__, elapsed)
        return result

    return wrapper


def configure_file_logging(path: Path) -> None:
    """테스트나 여러 CLI 호출에서도 중복 핸들러 없이 로그 파일을 설정한다."""

    path.parent.mkdir(parents=True, exist_ok=True)
    for handler in list(LOGGER.handlers):
        if isinstance(handler, logging.FileHandler):
            handler.close()
            LOGGER.removeHandler(handler)
    handler = logging.FileHandler(path, encoding="utf-8")
    handler.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(message)s"))
    LOGGER.addHandler(handler)
    LOGGER.setLevel(logging.INFO)
    LOGGER.propagate = False
