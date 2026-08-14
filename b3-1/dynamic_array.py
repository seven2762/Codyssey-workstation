"""직접 구현한 자료구조가 공통으로 사용하는 확장 가능한 배열이다."""


class DynamicArray:
    """가득 차면 용량을 두 배로 늘리는 인덱스 기반 배열이다."""

    def __init__(self, initial_capacity=8):
        if initial_capacity < 1:
            raise ValueError("initial_capacity must be positive")
        self._items = [None] * initial_capacity
        self._size = 0

    @property
    def capacity(self):
        return len(self._items)

    def append(self, value):
        """배열 마지막에 값을 추가한다."""
        if self._size == len(self._items):
            self._resize(len(self._items) * 2)
        self._items[self._size] = value
        self._size += 1

    def get(self, index):
        """유효한 인덱스의 값을 반환한다."""
        self._check_index(index)
        return self._items[index]

    def set(self, index, value):
        """유효한 인덱스의 값을 교체한다."""
        self._check_index(index)
        self._items[index] = value

    def remove(self, index):
        """인덱스의 값을 제거하고 뒤쪽 원소를 한 칸씩 당긴다."""
        self._check_index(index)
        removed = self._items[index]
        for position in range(index, self._size - 1):
            self._items[position] = self._items[position + 1]
        self._size -= 1
        self._items[self._size] = None
        return removed

    def pop(self):
        """마지막 값을 제거해 반환한다."""
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
        """표시와 테스트용으로 현재 원소의 복사본을 반환한다."""
        result = []
        for value in self:
            result.append(value)
        return result

    def _resize(self, new_capacity):
        """고정 길이 저장소를 더 큰 저장소로 교체한다."""
        resized = [None] * new_capacity
        for index in range(self._size):
            resized[index] = self._items[index]
        self._items = resized

    def _check_index(self, index):
        """인덱스가 현재 저장된 원소 범위에 있는지 검증한다."""
        if index < 0 or index >= self._size:
            raise IndexError("array index out of range")
