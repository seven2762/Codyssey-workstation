"""해시맵, LRU 리스트, 메모리 회계를 담당하는 저장소 클래스다."""

from doubly_linked_list import DoublyLinkedList
from hash_map import HashMap
from models import CacheEntry, MemoryInfo


class CacheStore:
    """문자열 엔트리의 저장·조회 순서·메모리 제한을 관리한다.

    TTL의 만료 시각 계산은 맡지 않는다. TTL은 TtlManager의 책임이고,
    이 클래스는 삭제 요청을 받았을 때 해시맵·LRU·메모리를 일관되게 갱신한다.
    """

    def __init__(self):
        self._entries = HashMap()
        self._lru = DoublyLinkedList()
        self._used_memory = 0
        self._maxmemory = 0
        self._evicted_keys = 0

    @property
    def used_memory(self):
        return self._used_memory

    @property
    def maxmemory(self):
        return self._maxmemory

    @property
    def evicted_keys(self):
        return self._evicted_keys

    def find(self, key):
        """키에 해당하는 엔트리를 반환한다. 조회 순서는 바꾸지 않는다."""
        return self._entries.get(key)

    def upsert(self, key, value):
        """엔트리를 저장하거나 갱신하고 최신 사용 위치로 이동시킨다."""
        entry = self.find(key)
        if entry is None:
            entry = CacheEntry(key, value)
            entry.lru_node = self._lru.insert_front(entry)
            self._entries.put(key, entry)
            self._used_memory += entry.memory_size
            return entry

        # 기존 값의 바이트 수를 먼저 빼고 새 값의 바이트 수를 반영한다.
        self._used_memory -= entry.memory_size
        entry.replace_value(value)
        self._used_memory += entry.memory_size
        self.touch(entry)
        return entry

    def touch(self, entry):
        """성공한 접근을 LRU 리스트의 가장 최근 사용 위치로 반영한다."""
        if entry.lru_node is not None:
            self._lru.move_to_front(entry.lru_node)

    def remove(self, key, evicted=False):
        """엔트리를 해시맵·LRU·메모리 회계에서 함께 제거한다."""
        entry = self._entries.remove(key)
        if entry is None:
            return False

        if entry.lru_node is not None and entry.lru_node.is_linked:
            self._lru.remove_node(entry.lru_node)
        entry.lru_node = None
        entry.clear_expiry()
        self._used_memory -= entry.memory_size
        if evicted:
            self._evicted_keys += 1
        return True

    def size(self):
        """현재 저장된 엔트리 수를 반환한다."""
        return self._entries.size()

    def keys(self):
        """현재 저장소의 키 목록을 반환한다."""
        return self._entries.keys()

    def set_maxmemory(self, maximum):
        """최대 메모리 제한을 설정한다. 0은 무제한이다."""
        self._maxmemory = maximum

    def is_entry_too_large(self, key, value):
        """단일 엔트리가 제한을 넘는지 저장 전에 판단한다."""
        if self._maxmemory == 0:
            return False
        return CacheEntry.calculate_memory_size(key, value) > self._maxmemory

    def evict_until_within_limit(self):
        """제한 이하가 될 때까지 가장 오래 사용하지 않은 엔트리를 제거한다."""
        if self._maxmemory == 0:
            return
        while self._used_memory > self._maxmemory:
            oldest_node = self._lru.peek_back()
            if oldest_node is None:
                return
            self.remove(oldest_node.data.key, evicted=True)

    def memory_info(self):
        """표현 계층에서 사용할 메모리 통계 객체를 만든다."""
        return MemoryInfo(self._used_memory, self._maxmemory, self._evicted_keys)
