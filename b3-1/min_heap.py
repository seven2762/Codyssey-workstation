"""A generic minimum heap backed by the custom dynamic array."""

from dynamic_array import DynamicArray


class MinHeap:
    """A binary min heap with O(log n) push/pop and O(1) peek."""

    def __init__(self):
        self._items = DynamicArray()

    def push(self, value):
        self._items.append(value)
        self._heapify_up(len(self._items) - 1)

    def pop(self):
        if len(self._items) == 0:
            return None
        minimum = self._items[0]
        last = self._items.pop()
        if len(self._items) > 0:
            self._items.set(0, last)
            self._heapify_down(0)
        return minimum

    def peek(self):
        return None if len(self._items) == 0 else self._items[0]

    def size(self):
        return len(self._items)

    def _heapify_up(self, index):
        while index > 0:
            parent = (index - 1) // 2
            if not self._less(self._items[index], self._items[parent]):
                break
            self._swap(index, parent)
            index = parent

    def _heapify_down(self, index):
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
        first_value = self._items[first]
        self._items.set(first, self._items[second])
        self._items.set(second, first_value)

    def _less(self, first, second):
        return first < second
