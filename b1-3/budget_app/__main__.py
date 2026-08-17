"""python -m budget_app 진입점."""

from __future__ import annotations

import os
import sys

from .cli import main


def _redirect_stdout_to_devnull() -> None:
    """닫힌 파이프를 인터프리터가 다시 flush하지 않도록 stdout을 교체한다."""

    try:
        null_descriptor = os.open(os.devnull, os.O_WRONLY)
        try:
            os.dup2(null_descriptor, sys.stdout.fileno())
        finally:
            os.close(null_descriptor)
    except (AttributeError, OSError, ValueError):
        return


exit_code = main()
try:
    sys.stdout.flush()
except BrokenPipeError:
    _redirect_stdout_to_devnull()
    exit_code = 0

raise SystemExit(exit_code)
