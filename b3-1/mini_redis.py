"""Core command engine for the CLI-based Mini Redis assignment."""

import shlex
import time

from doubly_linked_list import DoublyLinkedList
from hash_map import HashMap
from min_heap import MinHeap


OOM_ERROR = "(error) OOM command not allowed when used_memory > 'maxmemory'"
INTEGER_ERROR = "(error) ERR value is not an integer or out of range"


class CacheEntry:
    """The value stored in the hash map and tracked by the LRU list."""

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
        self.memory_size = len(key.encode("utf-8")) + len(value.encode("utf-8"))
        self.expires_at = None
        self.expire_version = 0
        self.lru_node = None


class ExpiryRecord:
    """A heap item; version makes stale TTL records safe to ignore lazily."""

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


class MiniRedis:
    """In-memory String store with custom HashMap, LRU list, and TTL heap."""

    def __init__(self):
        self._store = HashMap()
        self._lru = DoublyLinkedList()
        self._expiry_heap = MinHeap()
        self._expiry_sequence = 0
        self._used_memory = 0
        self._maxmemory = 0
        self._evicted_keys = 0

    def execute(self, command_line):
        """Parse and execute one command, returning Redis-style text output."""
        try:
            tokens = shlex.split(command_line)
        except ValueError:
            return "(error) ERR syntax error"
        if len(tokens) == 0:
            return ""

        command = tokens[0].upper()
        if command in ("EXIT", "QUIT"):
            return None
        if command == "SET":
            return self._set(tokens)
        if command == "GET":
            return self._get(tokens)
        if command == "DEL":
            return self._del(tokens)
        if command == "EXISTS":
            return self._exists(tokens)
        if command == "DBSIZE":
            return self._dbsize(tokens)
        if command == "KEYS":
            return self._keys(tokens)
        if command == "CONFIG":
            return self._config(tokens)
        if command == "INFO":
            return self._info(tokens)
        if command == "EXPIRE":
            return self._expire(tokens)
        if command == "TTL":
            return self._ttl(tokens)
        return "(error) ERR unknown command '{}'".format(tokens[0])

    def _set(self, tokens):
        if len(tokens) != 3:
            return self._wrong_arguments("SET")
        self._purge_expired()
        key, value = tokens[1], tokens[2]
        entry_size = len(key.encode("utf-8")) + len(value.encode("utf-8"))
        if self._maxmemory > 0 and entry_size > self._maxmemory:
            return OOM_ERROR

        entry = self._store.get(key)
        if entry is None:
            entry = CacheEntry(key, value)
            entry.lru_node = self._lru.insert_front(entry)
            self._store.put(key, entry)
            self._used_memory += entry_size
        else:
            self._used_memory -= entry.memory_size
            entry.value = value
            entry.memory_size = entry_size
            entry.expires_at = None
            entry.expire_version += 1
            self._used_memory += entry_size
            self._lru.move_to_front(entry.lru_node)

        self._evict_if_needed()
        return "OK"

    def _get(self, tokens):
        if len(tokens) != 2:
            return self._wrong_arguments("GET")
        entry = self._live_entry(tokens[1])
        if entry is None:
            return "(nil)"
        self._lru.move_to_front(entry.lru_node)
        return self._quote(entry.value)

    def _del(self, tokens):
        if len(tokens) != 2:
            return self._wrong_arguments("DEL")
        self._purge_expired()
        return "(integer) {}".format(1 if self._remove_entry(tokens[1]) else 0)

    def _exists(self, tokens):
        if len(tokens) != 2:
            return self._wrong_arguments("EXISTS")
        return "(integer) {}".format(1 if self._live_entry(tokens[1]) else 0)

    def _dbsize(self, tokens):
        if len(tokens) != 1:
            return self._wrong_arguments("DBSIZE")
        self._purge_expired()
        return "(integer) {}".format(self._store.size())

    def _keys(self, tokens):
        if len(tokens) != 1:
            return self._wrong_arguments("KEYS")
        self._purge_expired()
        keys = self._store.keys()
        if len(keys) == 0:
            return "(empty array)"
        lines = []
        for index in range(len(keys)):
            lines.append("{}) {}".format(index + 1, self._quote(keys[index])))
        return "\n".join(lines)

    def _config(self, tokens):
        if len(tokens) != 4:
            return self._wrong_arguments("CONFIG")
        if tokens[1].upper() != "SET" or tokens[2].lower() != "maxmemory":
            return "(error) ERR unknown subcommand '{}' for 'CONFIG'".format(tokens[1])
        maximum = self._parse_nonnegative_int(tokens[3])
        if maximum is None:
            return INTEGER_ERROR
        self._maxmemory = maximum
        return "OK"

    def _info(self, tokens):
        if len(tokens) != 2:
            return self._wrong_arguments("INFO")
        if tokens[1].lower() != "memory":
            return "(error) ERR unknown section '{}'".format(tokens[1])
        self._purge_expired()
        return "used_memory:{}\nmaxmemory:{}\nevicted_keys:{}".format(
            self._used_memory, self._maxmemory, self._evicted_keys
        )

    def _expire(self, tokens):
        if len(tokens) != 3:
            return self._wrong_arguments("EXPIRE")
        seconds = self._parse_int(tokens[2])
        if seconds is None:
            return INTEGER_ERROR
        entry = self._live_entry(tokens[1])
        if entry is None:
            return "(integer) 0"
        if seconds <= 0:
            self._remove_entry(tokens[1])
            return "(integer) 1"

        entry.expire_version += 1
        entry.expires_at = time.monotonic() + seconds
        self._expiry_sequence += 1
        self._expiry_heap.push(
            ExpiryRecord(
                entry.expires_at,
                entry.key,
                entry.expire_version,
                self._expiry_sequence,
            )
        )
        return "(integer) 1"

    def _ttl(self, tokens):
        if len(tokens) != 2:
            return self._wrong_arguments("TTL")
        entry = self._live_entry(tokens[1])
        if entry is None:
            return "(integer) -2"
        if entry.expires_at is None:
            return "(integer) -1"
        remaining = int(entry.expires_at - time.monotonic())
        if remaining < 0:
            self._remove_entry(tokens[1])
            return "(integer) -2"
        return "(integer) {}".format(remaining)

    def _live_entry(self, key):
        self._purge_expired()
        entry = self._store.get(key)
        if entry is not None and entry.expires_at is not None:
            if entry.expires_at <= time.monotonic():
                self._remove_entry(key)
                return None
        return entry

    def _purge_expired(self):
        now = time.monotonic()
        while self._expiry_heap.peek() is not None:
            record = self._expiry_heap.peek()
            if record.expire_at > now:
                return
            self._expiry_heap.pop()
            entry = self._store.get(record.key)
            if entry is None:
                continue
            if entry.expire_version != record.version:
                continue
            if entry.expires_at != record.expire_at:
                continue
            self._remove_entry(record.key)

    def _evict_if_needed(self):
        if self._maxmemory == 0:
            return
        while self._used_memory > self._maxmemory:
            oldest = self._lru.peek_back()
            if oldest is None:
                return
            self._remove_entry(oldest.data.key, evicted=True)

    def _remove_entry(self, key, evicted=False):
        entry = self._store.remove(key)
        if entry is None:
            return False
        if entry.lru_node is not None and entry.lru_node.is_linked:
            self._lru.remove_node(entry.lru_node)
        entry.lru_node = None
        entry.expires_at = None
        entry.expire_version += 1
        self._used_memory -= entry.memory_size
        if evicted:
            self._evicted_keys += 1
        return True

    def _parse_int(self, value):
        try:
            return int(value)
        except (TypeError, ValueError):
            return None

    def _parse_nonnegative_int(self, value):
        parsed = self._parse_int(value)
        if parsed is None or parsed < 0:
            return None
        return parsed

    def _wrong_arguments(self, command):
        return "(error) ERR wrong number of arguments for '{}' command".format(command)

    def _quote(self, value):
        escaped = value.replace("\\", "\\\\").replace('"', '\\"')
        escaped = escaped.replace("\n", "\\n").replace("\r", "\\r")
        return '"{}"'.format(escaped)
