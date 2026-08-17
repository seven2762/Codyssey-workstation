"""파싱된 Redis 명령을 기능별 핸들러로 실행한다."""

from redis_service import RedisService


class ResponseFormatter:
    """도메인 결과를 Redis CLI 스타일 문자열로 표현한다."""

    OOM_ERROR = "(error) OOM command not allowed when used_memory > 'maxmemory'"
    INTEGER_ERROR = "(error) ERR value is not an integer or out of range"

    @staticmethod
    def ok():
        return "OK"

    @staticmethod
    def nil():
        return "(nil)"

    @staticmethod
    def integer(value):
        return "(integer) {}".format(value)

    @staticmethod
    def syntax_error():
        return "(error) ERR syntax error"

    @staticmethod
    def wrong_arguments(command):
        return "(error) ERR wrong number of arguments for '{}' command".format(command)

    @staticmethod
    def quote(value):
        """줄바꿈과 따옴표를 CLI에서 읽기 쉬운 형태로 이스케이프한다."""
        escaped = value.replace("\\", "\\\\").replace('"', '\\"')
        escaped = escaped.replace("\n", "\\n").replace("\r", "\\r")
        return '"{}"'.format(escaped)


class StringCommandHandler:
    """SET, GET, DEL, EXISTS, DBSIZE, KEYS 명령을 담당한다."""

    def __init__(self, service):
        self._service = service

    def handle(self, command, arguments):
        if command == "SET":
            return self._set(arguments)
        if command == "GET":
            return self._get(arguments)
        if command == "DEL":
            return self._delete(arguments)
        if command == "EXISTS":
            return self._exists(arguments)
        if command == "DBSIZE":
            return self._dbsize(arguments)
        return self._keys(arguments)

    def _set(self, arguments):
        if len(arguments) != 2:
            return ResponseFormatter.wrong_arguments("SET")
        if not self._service.set_string(arguments[0], arguments[1]):
            return ResponseFormatter.OOM_ERROR
        return ResponseFormatter.ok()

    def _get(self, arguments):
        if len(arguments) != 1:
            return ResponseFormatter.wrong_arguments("GET")
        value = self._service.get_string(arguments[0])
        return ResponseFormatter.nil() if value is None else ResponseFormatter.quote(value)

    def _delete(self, arguments):
        if len(arguments) != 1:
            return ResponseFormatter.wrong_arguments("DEL")
        return ResponseFormatter.integer(1 if self._service.delete(arguments[0]) else 0)

    def _exists(self, arguments):
        if len(arguments) != 1:
            return ResponseFormatter.wrong_arguments("EXISTS")
        return ResponseFormatter.integer(1 if self._service.exists(arguments[0]) else 0)

    def _dbsize(self, arguments):
        if len(arguments) != 0:
            return ResponseFormatter.wrong_arguments("DBSIZE")
        return ResponseFormatter.integer(self._service.size())

    def _keys(self, arguments):
        if len(arguments) != 0:
            return ResponseFormatter.wrong_arguments("KEYS")
        keys = self._service.keys()
        if len(keys) == 0:
            return "(empty array)"
        lines = []
        for index in range(len(keys)):
            lines.append("{}) {}".format(index + 1, ResponseFormatter.quote(keys[index])))
        return "\n".join(lines)


class MemoryCommandHandler:
    """CONFIG SET maxmemory와 INFO memory 명령을 담당한다."""

    def __init__(self, service):
        self._service = service

    def handle(self, command, arguments):
        if command == "CONFIG":
            return self._config(arguments)
        return self._info(arguments)

    def _config(self, arguments):
        if len(arguments) != 3:
            return ResponseFormatter.wrong_arguments("CONFIG")
        if arguments[0].upper() != "SET" or arguments[1].lower() != "maxmemory":
            return "(error) ERR unknown subcommand '{}' for 'CONFIG'".format(arguments[0])
        maximum = self._parse_nonnegative_int(arguments[2])
        if maximum is None:
            return ResponseFormatter.INTEGER_ERROR
        self._service.configure_maxmemory(maximum)
        return ResponseFormatter.ok()

    def _info(self, arguments):
        if len(arguments) != 1:
            return ResponseFormatter.wrong_arguments("INFO")
        if arguments[0].lower() != "memory":
            return "(error) ERR unknown section '{}'".format(arguments[0])
        info = self._service.memory_info()
        return "used_memory:{}\nmaxmemory:{}\nevicted_keys:{}".format(
            info.used_memory, info.maxmemory, info.evicted_keys
        )

    def _parse_nonnegative_int(self, value):
        try:
            parsed = int(value)
        except (TypeError, ValueError):
            return None
        return parsed if parsed >= 0 else None


class TtlCommandHandler:
    """EXPIRE와 TTL 명령을 담당한다."""

    def __init__(self, service):
        self._service = service

    def handle(self, command, arguments):
        if command == "EXPIRE":
            return self._expire(arguments)
        return self._ttl(arguments)

    def _expire(self, arguments):
        if len(arguments) != 2:
            return ResponseFormatter.wrong_arguments("EXPIRE")
        seconds = self._parse_int(arguments[1])
        if seconds is None:
            return ResponseFormatter.INTEGER_ERROR
        return ResponseFormatter.integer(
            1 if self._service.expire(arguments[0], seconds) else 0
        )

    def _ttl(self, arguments):
        if len(arguments) != 1:
            return ResponseFormatter.wrong_arguments("TTL")
        return ResponseFormatter.integer(self._service.ttl(arguments[0]))

    def _parse_int(self, value):
        try:
            return int(value)
        except (TypeError, ValueError):
            return None


class CommandDispatcher:
    """명령 종류에 따라 적절한 핸들러에 실행을 위임한다."""

    def __init__(self, service=None):
        redis_service = RedisService() if service is None else service
        self._string_handler = StringCommandHandler(redis_service)
        self._memory_handler = MemoryCommandHandler(redis_service)
        self._ttl_handler = TtlCommandHandler(redis_service)

    def dispatch(self, command):
        """파싱된 명령의 처리 결과를 반환한다. 종료 명령은 None을 반환한다."""
        if command.name == "":
            return ""
        if command.name in ("EXIT", "QUIT"):
            return None
        if command.name in ("SET", "GET", "DEL", "EXISTS", "DBSIZE", "KEYS"):
            return self._string_handler.handle(command.name, command.arguments)
        if command.name in ("CONFIG", "INFO"):
            return self._memory_handler.handle(command.name, command.arguments)
        if command.name in ("EXPIRE", "TTL"):
            return self._ttl_handler.handle(command.name, command.arguments)
        return "(error) ERR unknown command '{}'".format(command.original_name)
