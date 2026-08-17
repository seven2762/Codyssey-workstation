import unittest

from command_parser import CommandParseError, CommandParser


class CommandParserTest(unittest.TestCase):
    def test_parser_keeps_quoted_value_as_one_argument(self):
        command = CommandParser().parse('SET greeting "hello world"')

        self.assertEqual(command.name, "SET")
        self.assertEqual(command.arguments, ["greeting", "hello world"])

    def test_parser_reports_unclosed_quote_as_syntax_error(self):
        with self.assertRaises(CommandParseError):
            CommandParser().parse('SET greeting "hello world')


if __name__ == "__main__":
    unittest.main()
