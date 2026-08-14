import unittest

from doubly_linked_list import DoublyLinkedList
from hash_map import HashMap
from min_heap import MinHeap


class DoublyLinkedListTest(unittest.TestCase):
    def test_insert_move_and_remove_are_linked_correctly(self):
        linked_list = DoublyLinkedList()
        first = linked_list.insert_front("first")
        last = linked_list.insert_back("last")
        middle = linked_list.insert_after(first, "middle")

        self.assertEqual(linked_list.to_list(), ["first", "middle", "last"])
        linked_list.move_to_front(last)
        self.assertEqual(linked_list.to_list(), ["last", "first", "middle"])

        linked_list.remove_node(first)
        self.assertEqual(linked_list.to_list(), ["last", "middle"])
        self.assertIsNone(first.prev)
        self.assertIsNone(first.next)
        self.assertEqual(linked_list.remove_front().data, "last")
        self.assertEqual(linked_list.remove_back().data, "middle")
        self.assertTrue(linked_list.is_empty())

    def test_remove_from_empty_list_returns_none(self):
        linked_list = DoublyLinkedList()
        self.assertIsNone(linked_list.remove_front())
        self.assertIsNone(linked_list.remove_back())


class HashMapTest(unittest.TestCase):
    def test_put_get_remove_contains_and_keys(self):
        hash_map = HashMap(initial_capacity=2)
        hash_map.put("a", 1)
        hash_map.put("b", 2)
        hash_map.put("a", 3)

        self.assertEqual(hash_map.get("a"), 3)
        self.assertEqual(hash_map.get("missing"), None)
        self.assertTrue(hash_map.contains("b"))
        self.assertEqual(hash_map.size(), 2)
        self.assertCountEqual(hash_map.keys().to_list(), ["a", "b"])
        self.assertEqual(hash_map.remove("b"), 2)
        self.assertFalse(hash_map.contains("b"))
        self.assertEqual(hash_map.size(), 1)

    def test_resizes_when_load_factor_exceeds_point_seventy_five(self):
        hash_map = HashMap(initial_capacity=4)
        hash_map.put("one", 1)
        hash_map.put("two", 2)
        hash_map.put("three", 3)

        self.assertEqual(hash_map.capacity, 8)
        self.assertEqual(hash_map.get("one"), 1)
        self.assertEqual(hash_map.get("two"), 2)
        self.assertEqual(hash_map.get("three"), 3)


class MinHeapTest(unittest.TestCase):
    def test_push_peek_pop_returns_smallest_first(self):
        heap = MinHeap()
        heap.push(5)
        heap.push(1)
        heap.push(3)

        self.assertEqual(heap.peek(), 1)
        self.assertEqual(heap.size(), 3)
        self.assertEqual(heap.pop(), 1)
        self.assertEqual(heap.pop(), 3)
        self.assertEqual(heap.pop(), 5)
        self.assertIsNone(heap.pop())


if __name__ == "__main__":
    unittest.main()
