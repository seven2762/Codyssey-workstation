"""Mini Redis 도메인 객체를 정의한다."""


class CacheEntry:
    """키, 값, TTL, LRU 노드 정보를 한데 보관하는 캐시 엔트리다."""

    __slots__ = (
        "key",
        "value",
        "memory_size",
        "expires_at",
        "expire_version",
        "lru_node",
    )

    def __init__(self, key, value):
        self.key = key
        self.value = value
        self.memory_size = self.calculate_memory_size(key, value)
        self.expires_at = None
        self.expire_version = 0
        self.lru_node = None

    @staticmethod
    def calculate_memory_size(key, value):
        """과제의 used_memory 기준에 맞춰 UTF-8 바이트 수를 계산한다."""
        return len(key.encode("utf-8")) + len(value.encode("utf-8"))

    def replace_value(self, value):
        """값과 메모리 사용량을 함께 갱신한다."""
        self.value = value
        self.memory_size = self.calculate_memory_size(self.key, value)

    def set_expiry(self, expire_at):
        """새 TTL 버전을 발급하고 만료 시각을 기록한다."""
        self.expire_version += 1
        self.expires_at = expire_at
        return self.expire_version

    def clear_expiry(self):
        """기존 힙 레코드를 무효화하도록 TTL 버전을 증가시킨다."""
        self.expires_at = None
        self.expire_version += 1

    def matches_expiry_record(self, expire_at, version):
        """힙에서 꺼낸 레코드가 현재 엔트리의 TTL인지 확인한다."""
        return self.expires_at == expire_at and self.expire_version == version


class ExpiryRecord:
    """최소 힙에 저장하는 TTL 레코드다.

    같은 시각에 만료되는 키가 있을 수 있으므로 sequence로 순서를 안정화한다.
    """

    __slots__ = ("expire_at", "key", "version", "sequence")

    def __init__(self, expire_at, key, version, sequence):
        self.expire_at = expire_at
        self.key = key
        self.version = version
        self.sequence = sequence

    def __lt__(self, other):
        if self.expire_at != other.expire_at:
            return self.expire_at < other.expire_at
        return self.sequence < other.sequence


class MemoryInfo:
    """INFO memory 응답에 필요한 메모리 통계 값이다."""

    __slots__ = ("used_memory", "maxmemory", "evicted_keys")

    def __init__(self, used_memory, maxmemory, evicted_keys):
        self.used_memory = used_memory
        self.maxmemory = maxmemory
        self.evicted_keys = evicted_keys
