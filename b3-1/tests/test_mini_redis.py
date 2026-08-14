import time
import unittest

from mini_redis import MiniRedis


class MiniRedisCommandTest(unittest.TestCase):
    def test_string_commands_and_quoted_values(self):
        redis = MiniRedis()

        self.assertEqual(redis.execute('SET greeting "hello world"'), "OK")
        self.assertEqual(redis.execute("GET greeting"), '"hello world"')
        self.assertEqual(redis.execute("EXISTS greeting"), "(integer) 1")
        self.assertEqual(redis.execute("DBSIZE"), "(integer) 1")
        self.assertEqual(redis.execute("DEL greeting"), "(integer) 1")
        self.assertEqual(redis.execute("GET greeting"), "(nil)")
        self.assertEqual(redis.execute("DEL greeting"), "(integer) 0")

    def test_keys_returns_all_live_keys(self):
        redis = MiniRedis()
        redis.execute("SET user:1 Alice")
        redis.execute("SET user:2 Bob")

        output = redis.execute("KEYS")
        self.assertIn('"user:1"', output)
        self.assertIn('"user:2"', output)

    def test_lru_evicts_least_recently_used_key_and_reports_memory(self):
        redis = MiniRedis()
        self.assertEqual(redis.execute("CONFIG SET maxmemory 10"), "OK")
        self.assertEqual(redis.execute("SET a 1234"), "OK")
        self.assertEqual(redis.execute("SET b 5678"), "OK")
        self.assertEqual(redis.execute("GET a"), '"1234"')
        self.assertEqual(redis.execute("SET c 9"), "OK")

        self.assertEqual(redis.execute("GET b"), "(nil)")
        self.assertEqual(redis.execute("GET a"), '"1234"')
        self.assertEqual(redis.execute("GET c"), '"9"')
        info = redis.execute("INFO memory")
        self.assertIn("used_memory:7", info)
        self.assertIn("maxmemory:10", info)
        self.assertIn("evicted_keys:1", info)

    def test_oversized_single_entry_is_rejected_without_storing(self):
        redis = MiniRedis()
        redis.execute("CONFIG SET maxmemory 3")

        self.assertEqual(
            redis.execute("SET abc value"),
            "(error) OOM command not allowed when used_memory > 'maxmemory'",
        )
        self.assertEqual(redis.execute("EXISTS abc"), "(integer) 0")

    def test_memory_uses_utf8_byte_length(self):
        redis = MiniRedis()
        redis.execute("CONFIG SET maxmemory 11")

        self.assertEqual(
            redis.execute("SET 키 값"),
            "(error) OOM command not allowed when used_memory > 'maxmemory'",
        )

    def test_expire_ttl_and_set_reset_ttl(self):
        redis = MiniRedis()
        redis.execute("SET session active")
        self.assertEqual(redis.execute("EXPIRE session 0"), "(integer) 1")
        self.assertEqual(redis.execute("TTL session"), "(integer) -2")

        redis.execute("SET session active")
        self.assertEqual(redis.execute("EXPIRE session 1"), "(integer) 1")
        self.assertIn(redis.execute("TTL session"), ("(integer) 0", "(integer) 1"))
        redis.execute("SET session renewed")
        self.assertEqual(redis.execute("TTL session"), "(integer) -1")

    def test_expired_key_is_removed_before_reads(self):
        redis = MiniRedis()
        redis.execute("SET short lived")
        redis.execute("EXPIRE short 1")
        time.sleep(1.1)

        self.assertEqual(redis.execute("GET short"), "(nil)")
        self.assertEqual(redis.execute("EXISTS short"), "(integer) 0")
        self.assertEqual(redis.execute("DBSIZE"), "(integer) 0")

    def test_error_messages_are_redis_style(self):
        redis = MiniRedis()

        self.assertEqual(
            redis.execute("GET"),
            "(error) ERR wrong number of arguments for 'GET' command",
        )
        self.assertEqual(
            redis.execute("CONFIG SET maxmemory abc"),
            "(error) ERR value is not an integer or out of range",
        )
        self.assertEqual(
            redis.execute("HELLO"),
            "(error) ERR unknown command 'HELLO'",
        )


if __name__ == "__main__":
    unittest.main()
