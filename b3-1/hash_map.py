"""dict와 set 없이 체이닝 방식으로 구현한 해시맵이다."""

from doubly_linked_list import DoublyLinkedList
from dynamic_array import DynamicArray


class _Entry:
    """해시 버킷 연결 리스트에 저장되는 키-값 쌍이다."""
    __slots__ = ("key", "value")

    def __init__(self, key, value):
        self.key = key
        self.value = value


class HashMap:
    """직접 구현한 연결 리스트 버킷을 사용하는 문자열 키 해시맵이다."""

    LOAD_FACTOR_LIMIT = 0.75

    def __init__(self, initial_capacity=8):
        if initial_capacity < 1:
            raise ValueError("initial_capacity must be positive")
        self.capacity = initial_capacity
        self._buckets = self._new_buckets(initial_capacity)
        self._size = 0

    def put(self, key, value):
        """키-값을 저장하거나 교체하고, 교체 전 값을 반환한다."""
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
        """키의 값을 반환하고 없으면 기본값을 반환한다."""
        bucket = self._buckets[self._bucket_index(key)]
        node = self._find_node(bucket, key)
        return default if node is None else node.data.value

    def remove(self, key, default=None):
        """키를 제거하고 기존 값을 반환한다."""
        bucket = self._buckets[self._bucket_index(key)]
        node = self._find_node(bucket, key)
        if node is None:
            return default
        value = node.data.value
        bucket.remove_node(node)
        self._size -= 1
        return value

    def contains(self, key):
        """키 존재 여부를 반환한다."""
        bucket = self._buckets[self._bucket_index(key)]
        return self._find_node(bucket, key) is not None

    def keys(self):
        """모든 버킷을 순회해 키를 동적 배열에 담아 반환한다."""
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
        """저장된 키 개수를 반환한다."""
        return self._size

    def _hash(self, key):
        """문자 코드와 31진 누적을 이용해 문자열 해시값을 만든다."""
        if not isinstance(key, str):
            raise TypeError("HashMap keys must be strings")
        hash_value = 0
        for character in key:
            hash_value = (hash_value * 31 + ord(character)) & 0x7FFFFFFF
        return hash_value

    def _bucket_index(self, key):
        """해시값을 현재 버킷 범위의 인덱스로 변환한다."""
        return self._hash(key) % self.capacity

    def _new_buckets(self, capacity):
        """지정한 수만큼 빈 연결 리스트 버킷을 생성한다."""
        buckets = DynamicArray(capacity)
        for _ in range(capacity):
            buckets.append(DoublyLinkedList())
        return buckets

    def _find_node(self, bucket, key):
        """체이닝된 버킷에서 키를 가진 노드를 찾는다."""
        node = bucket.peek_front()
        while node is not None:
            if node.data.key == key:
                return node
            node = node.next
            if node is bucket._tail:
                break
        return None

    def _resize(self, new_capacity):
        """로드 팩터 초과 시 버킷을 두 배로 늘려 모든 엔트리를 재배치한다."""
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
        """리해시 중인 엔트리를 크기 변경 없이 새 버킷에 넣는다."""
        bucket = self._buckets[self._bucket_index(key)]
        bucket.insert_front(_Entry(key, value))
