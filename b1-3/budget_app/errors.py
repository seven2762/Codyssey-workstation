"""사용자에게 안전하게 보여 줄 애플리케이션 예외."""

from __future__ import annotations


class AppError(Exception):
    """예상 가능한 오류와 해결 힌트를 함께 전달한다."""

    def __init__(self, message: str, hint: str = "입력값과 파일 경로를 확인해 주세요.") -> None:
        super().__init__(message)
        self.hint = hint


class ValidationError(AppError):
    """사용자 입력이나 저장 데이터의 값이 유효하지 않다."""


class NotFoundError(AppError):
    """요청한 리소스가 존재하지 않는다."""


class ConflictError(AppError):
    """현재 데이터 상태 때문에 요청을 수행할 수 없다."""


class StorageError(AppError):
    """파일을 안전하게 읽거나 쓸 수 없다."""
