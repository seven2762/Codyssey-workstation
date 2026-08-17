"""CLI와 도메인 계층을 연결하는 Mini Redis 진입 클래스다."""

from command_handler import CommandDispatcher, ResponseFormatter
from command_parser import CommandParseError, CommandParser
from redis_service import RedisService


class MiniRedis:
    """명령 파싱과 실행 위임만 담당하는 얇은 애플리케이션 퍼사드다."""

    def __init__(self, service=None, parser=None, dispatcher=None):
        redis_service = RedisService() if service is None else service
        self._parser = CommandParser() if parser is None else parser
        self._dispatcher = (
            CommandDispatcher(redis_service) if dispatcher is None else dispatcher
        )

    def execute(self, command_line):
        """REPL 한 줄을 실행하고 Redis CLI 스타일 응답을 반환한다."""
        try:
            command = self._parser.parse(command_line)
        except CommandParseError:
            return ResponseFormatter.syntax_error()
        return self._dispatcher.dispatch(command)
