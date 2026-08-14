"""직접 구현한 동적 배열을 저장소로 사용하는 최소 힙이다."""

from dynamic_array import DynamicArray


class MinHeap:
    """삽입·삭제는 O(log n), 최솟값 조회는 O(1)인 이진 최소 힙이다."""

    def __init__(self):
        self._items = DynamicArray()

    def push(self, value):
        """값을 추가하고 부모 방향으로 정렬한다."""
        self._items.append(value)
        self._heapify_up(len(self._items) - 1)

    def pop(self):
        """최솟값을 제거해 반환한다."""
        if len(self._items) == 0:
            return None
        minimum = self._items[0]
        last = self._items.pop()
        if len(self._items) > 0:
            self._items.set(0, last)
            self._heapify_down(0)
        return minimum

    def peek(self):
        """최솟값을 제거하지 않고 반환한다."""
        return None if len(self._items) == 0 else self._items[0]

    def size(self):
        """힙 원소 수를 반환한다."""
        return len(self._items)

    def _heapify_up(self, index):
        """새 원소를 부모와 비교해 위로 이동시킨다."""
        while index > 0:
            parent = (index - 1) // 2
            if not self._less(self._items[index], self._items[parent]):
                break
            self._swap(index, parent)
            index = parent

    def _heapify_down(self, index):
        """루트로 올라온 원소를 자식과 비교해 아래로 이동시킨다."""
        size = len(self._items)
        while True:
            left = index * 2 + 1
            right = left + 1
            smallest = index
            if left < size and self._less(self._items[left], self._items[smallest]):
                smallest = left
            if right < size and self._less(self._items[right], self._items[smallest]):
                smallest = right
            if smallest == index:
                return
            self._swap(index, smallest)
            index = smallest

    def _swap(self, first, second):
        """두 인덱스의 원소를 교환한다."""
        first_value = self._items[first]
        self._items.set(first, self._items[second])
        self._items.set(second, first_value)

    def _less(self, first, second):
        """두 원소의 최소 힙 우선순위를 비교한다."""
        return first < second
