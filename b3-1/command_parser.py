"""REPL 입력을 명령 객체로 변환하는 파서다."""

import shlex


class CommandParseError(ValueError):
    """따옴표가 닫히지 않는 등 명령 문법이 잘못됐을 때 발생한다."""


class ParsedCommand:
    """파싱된 명령 이름과 인자를 보관하는 값 객체다."""

    __slots__ = ("name", "original_name", "arguments")

    def __init__(self, name, original_name, arguments):
        self.name = name
        self.original_name = original_name
        self.arguments = arguments


class CommandParser:
    """큰따옴표로 묶인 공백 포함 값을 지원하는 CLI 명령 파서다."""

    def parse(self, command_line):
        """입력 한 줄을 ParsedCommand로 변환한다."""
        try:
            tokens = shlex.split(command_line)
        except ValueError as error:
            raise CommandParseError() from error
        if len(tokens) == 0:
            return ParsedCommand("", "", [])
        return ParsedCommand(tokens[0].upper(), tokens[0], tokens[1:])
