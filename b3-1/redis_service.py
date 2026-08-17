"""Mini Redis의 도메인 동작을 조합하는 서비스 계층이다."""

from cache_store import CacheStore
from ttl_manager import TtlManager


class RedisService:
    """명령 형식과 무관한 문자열 저장소 동작을 제공한다."""

    def __init__(self, cache_store=None, ttl_manager=None):
        self._cache_store = CacheStore() if cache_store is None else cache_store
        self._ttl_manager = TtlManager() if ttl_manager is None else ttl_manager

    def set_string(self, key, value):
        """문자열을 저장하고, 단일 엔트리 OOM 여부를 반환한다."""
        self._purge_expired()
        if self._cache_store.is_entry_too_large(key, value):
            return False
        entry = self._cache_store.upsert(key, value)
        # SET은 기존 TTL을 제거해야 하므로 TTL 관리자에 위임한다.
        self._ttl_manager.clear(entry)
        self._cache_store.evict_until_within_limit()
        return True

    def get_string(self, key):
        """살아 있는 문자열을 조회하고 성공한 경우에만 LRU를 갱신한다."""
        entry = self._find_live_entry(key)
        if entry is None:
            return None
        self._cache_store.touch(entry)
        return entry.value

    def delete(self, key):
        """키를 삭제하고 성공 여부를 반환한다."""
        self._purge_expired()
        return self._cache_store.remove(key)

    def exists(self, key):
        """키가 만료되지 않은 상태로 존재하는지 반환한다."""
        return self._find_live_entry(key) is not None

    def size(self):
        """만료 키를 정리한 뒤 저장된 키 수를 반환한다."""
        self._purge_expired()
        return self._cache_store.size()

    def keys(self):
        """만료 키를 제외한 전체 키 목록을 반환한다."""
        self._purge_expired()
        return self._cache_store.keys()

    def configure_maxmemory(self, maximum):
        """최대 메모리 제한을 설정한다."""
        self._cache_store.set_maxmemory(maximum)

    def memory_info(self):
        """만료 키를 반영한 최신 메모리 통계를 반환한다."""
        self._purge_expired()
        return self._cache_store.memory_info()

    def expire(self, key, seconds):
        """키의 TTL을 설정하고 대상 키가 있었는지 반환한다."""
        entry = self._find_live_entry(key)
        if entry is None:
            return False
        if seconds <= 0:
            self._cache_store.remove(key)
            return True
        self._ttl_manager.assign(entry, seconds)
        return True

    def ttl(self, key):
        """Redis 규칙에 맞춰 TTL 결과를 반환한다.

        -2는 키 없음, -1은 TTL 미설정, 0 이상은 남은 초를 뜻한다.
        """
        entry = self._find_live_entry(key)
        if entry is None:
            return -2
        if entry.expires_at is None:
            return -1
        remaining = self._ttl_manager.remaining_seconds(entry)
        if remaining < 0:
            self._cache_store.remove(key)
            return -2
        return remaining

    def _find_live_entry(self, key):
        self._purge_expired()
        entry = self._cache_store.find(key)
        if entry is not None and self._ttl_manager.is_expired(entry):
            self._cache_store.remove(key)
            return None
        return entry

    def _purge_expired(self):
        self._ttl_manager.purge_expired(self._cache_store)
