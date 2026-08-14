"""최소 힙을 사용해 TTL을 등록하고 만료 키를 정리한다."""

import time

from min_heap import MinHeap
from models import ExpiryRecord


class TtlManager:
    """TTL 레코드의 생성·검증·정리를 담당한다.

    저장소는 인자로 받아 느슨하게 결합한다. 저장소는 find와 remove만 제공하면
    되므로, TTL 정책은 HashMap과 LRU의 구체적인 구현을 알 필요가 없다.
    """

    def __init__(self, clock=None):
        self._clock = time.monotonic if clock is None else clock
        self._expiry_heap = MinHeap()
        self._sequence = 0

    def assign(self, entry, seconds):
        """엔트리에 새 만료 시각을 부여하고 최소 힙에 등록한다."""
        expire_at = self._clock() + seconds
        version = entry.set_expiry(expire_at)
        self._sequence += 1
        self._expiry_heap.push(
            ExpiryRecord(expire_at, entry.key, version, self._sequence)
        )

    def clear(self, entry):
        """SET 덮어쓰기처럼 기존 TTL을 없애야 할 때 호출한다."""
        entry.clear_expiry()

    def purge_expired(self, cache_store):
        """만료된 현재 TTL 레코드만 찾아 저장소에서 제거한다."""
        now = self._clock()
        while self._expiry_heap.peek() is not None:
            record = self._expiry_heap.peek()
            if record.expire_at > now:
                return
            self._expiry_heap.pop()
            entry = cache_store.find(record.key)
            if entry is None:
                continue
            if not entry.matches_expiry_record(record.expire_at, record.version):
                # TTL이 덮어써졌거나 키가 재생성된 오래된 힙 레코드다.
                continue
            cache_store.remove(record.key)

    def is_expired(self, entry):
        """힙 정리 사이에 막 만료된 엔트리를 즉시 판별한다."""
        return entry.expires_at is not None and entry.expires_at <= self._clock()

    def remaining_seconds(self, entry):
        """Redis TTL 규칙처럼 남은 시간을 정수 초로 내림해 반환한다."""
        return int(entry.expires_at - self._clock())
