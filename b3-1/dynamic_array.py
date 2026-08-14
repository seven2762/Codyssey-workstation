"""A small growable array used by the hand-written data structures."""


class DynamicArray:
    """An indexed array that doubles its capacity when it becomes full."""

    def __init__(self, initial_capacity=8):
        if initial_capacity < 1:
            raise ValueError("initial_capacity must be positive")
        self._items = [None] * initial_capacity
        self._size = 0

    @property
    def capacity(self):
        return len(self._items)

    def append(self, value):
        if self._size == len(self._items):
            self._resize(len(self._items) * 2)
        self._items[self._size] = value
        self._size += 1

    def get(self, index):
        self._check_index(index)
        return self._items[index]

    def set(self, index, value):
        self._check_index(index)
        self._items[index] = value

    def remove(self, index):
        self._check_index(index)
        removed = self._items[index]
        for position in range(index, self._size - 1):
            self._items[position] = self._items[position + 1]
        self._size -= 1
        self._items[self._size] = None
        return removed

    def pop(self):
        if self._size == 0:
            return None
        return self.remove(self._size - 1)

    def __len__(self):
        return self._size

    def __getitem__(self, index):
        return self.get(index)

    def __iter__(self):
        for index in range(self._size):
            yield self._items[index]

    def to_list(self):
        """Return a copy for presentation and test assertions."""
        result = []
        for value in self:
            result.append(value)
        return result

    def _resize(self, new_capacity):
        resized = [None] * new_capacity
        for index in range(self._size):
            resized[index] = self._items[index]
        self._items = resized

    def _check_index(self, index):
        if index < 0 or index >= self._size:
            raise IndexError("array index out of range")
