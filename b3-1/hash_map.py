"""A separate-chaining hash map without using dict or set."""

from doubly_linked_list import DoublyLinkedList
from dynamic_array import DynamicArray


class _Entry:
    __slots__ = ("key", "value")

    def __init__(self, key, value):
        self.key = key
        self.value = value


class HashMap:
    """A string-keyed hash map whose buckets are hand-written linked lists."""

    LOAD_FACTOR_LIMIT = 0.75

    def __init__(self, initial_capacity=8):
        if initial_capacity < 1:
            raise ValueError("initial_capacity must be positive")
        self.capacity = initial_capacity
        self._buckets = self._new_buckets(initial_capacity)
        self._size = 0

    def put(self, key, value):
        """Insert or replace a value and return the previous value if present."""
        bucket = self._buckets[self._bucket_index(key)]
        node = self._find_node(bucket, key)
        if node is not None:
            previous = node.data.value
            node.data.value = value
            return previous

        if (self._size + 1) / self.capacity > self.LOAD_FACTOR_LIMIT:
            self._resize(self.capacity * 2)
            bucket = self._buckets[self._bucket_index(key)]
        bucket.insert_front(_Entry(key, value))
        self._size += 1
        return None

    def get(self, key, default=None):
        bucket = self._buckets[self._bucket_index(key)]
        node = self._find_node(bucket, key)
        return default if node is None else node.data.value

    def remove(self, key, default=None):
        bucket = self._buckets[self._bucket_index(key)]
        node = self._find_node(bucket, key)
        if node is None:
            return default
        value = node.data.value
        bucket.remove_node(node)
        self._size -= 1
        return value

    def contains(self, key):
        bucket = self._buckets[self._bucket_index(key)]
        return self._find_node(bucket, key) is not None

    def keys(self):
        result = DynamicArray()
        for bucket_index in range(self.capacity):
            bucket = self._buckets[bucket_index]
            node = bucket.peek_front()
            while node is not None:
                result.append(node.data.key)
                node = node.next
                if node is bucket._tail:
                    break
        return result

    def size(self):
        return self._size

    def _hash(self, key):
        if not isinstance(key, str):
            raise TypeError("HashMap keys must be strings")
        hash_value = 0
        for character in key:
            hash_value = (hash_value * 31 + ord(character)) & 0x7FFFFFFF
        return hash_value

    def _bucket_index(self, key):
        return self._hash(key) % self.capacity

    def _new_buckets(self, capacity):
        buckets = DynamicArray(capacity)
        for _ in range(capacity):
            buckets.append(DoublyLinkedList())
        return buckets

    def _find_node(self, bucket, key):
        node = bucket.peek_front()
        while node is not None:
            if node.data.key == key:
                return node
            node = node.next
            if node is bucket._tail:
                break
        return None

    def _resize(self, new_capacity):
        old_buckets = self._buckets
        self.capacity = new_capacity
        self._buckets = self._new_buckets(new_capacity)
        for bucket_index in range(len(old_buckets)):
            old_bucket = old_buckets[bucket_index]
            node = old_bucket.peek_front()
            while node is not None:
                self._insert_existing(node.data.key, node.data.value)
                node = node.next
                if node is old_bucket._tail:
                    break

    def _insert_existing(self, key, value):
        bucket = self._buckets[self._bucket_index(key)]
        bucket.insert_front(_Entry(key, value))
