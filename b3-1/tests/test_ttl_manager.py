import unittest

from cache_store import CacheStore
from ttl_manager import TtlManager


class FakeClock:
    def __init__(self):
        self.now = 100.0

    def __call__(self):
        return self.now

    def advance(self, seconds):
        self.now += seconds


class TtlManagerTest(unittest.TestCase):
    def test_purge_removes_entry_after_expiry_time(self):
        clock = FakeClock()
        store = CacheStore()
        ttl_manager = TtlManager(clock=clock)
        entry = store.upsert("session", "active")
        ttl_manager.assign(entry, 3)

        self.assertEqual(ttl_manager.remaining_seconds(entry), 3)
        clock.advance(3)
        ttl_manager.purge_expired(store)

        self.assertIsNone(store.find("session"))

    def test_reassigned_ttl_ignores_stale_heap_record(self):
        clock = FakeClock()
        store = CacheStore()
        ttl_manager = TtlManager(clock=clock)
        entry = store.upsert("session", "active")
        ttl_manager.assign(entry, 2)
        ttl_manager.assign(entry, 5)

        clock.advance(2)
        ttl_manager.purge_expired(store)
        self.assertIsNotNone(store.find("session"))

        clock.advance(3)
        ttl_manager.purge_expired(store)
        self.assertIsNone(store.find("session"))


if __name__ == "__main__":
    unittest.main()
