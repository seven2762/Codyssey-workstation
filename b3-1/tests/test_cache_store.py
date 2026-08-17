import unittest

from cache_store import CacheStore


class CacheStoreTest(unittest.TestCase):
    def test_lru_eviction_is_the_store_responsibility(self):
        store = CacheStore()
        first = store.upsert("a", "1234")
        store.upsert("b", "5678")
        store.set_maxmemory(10)

        store.touch(first)
        store.upsert("c", "9")
        store.evict_until_within_limit()

        self.assertIsNone(store.find("b"))
        self.assertIsNotNone(store.find("a"))
        self.assertIsNotNone(store.find("c"))
        self.assertEqual(store.used_memory, 7)
        self.assertEqual(store.evicted_keys, 1)

    def test_remove_updates_memory_and_lru_state_together(self):
        store = CacheStore()
        store.upsert("key", "value")

        self.assertTrue(store.remove("key"))
        self.assertEqual(store.used_memory, 0)
        self.assertEqual(store.size(), 0)
        self.assertFalse(store.remove("key"))

    def test_entry_size_can_be_checked_before_mutating_store(self):
        store = CacheStore()
        store.set_maxmemory(3)

        self.assertTrue(store.is_entry_too_large("abc", "value"))
        self.assertFalse(store.is_entry_too_large("a", "b"))


if __name__ == "__main__":
    unittest.main()
