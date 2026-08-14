"""Doubly linked list implementation used for LRU order and hash buckets."""


class Node:
    """A list node with the required prev, next, and data fields."""

    __slots__ = ("prev", "next", "data", "_linked")

    def __init__(self, data=None):
        self.prev = None
        self.next = None
        self.data = data
        self._linked = False

    @property
    def is_linked(self):
        return self._linked


class DoublyLinkedList:
    """A sentinel-based doubly linked list with O(1) structural operations."""

    def __init__(self):
        self._head = Node()
        self._tail = Node()
        self._head.next = self._tail
        self._tail.prev = self._head
        self._size = 0

    def insert_front(self, data):
        return self.insert_after(self._head, data)

    def insert_back(self, data):
        return self.insert_before(self._tail, data)

    def insert_after(self, node, data):
        if node is self._tail:
            raise ValueError("cannot insert after the tail sentinel")
        new_node = Node(data)
        self._link_between(node, node.next, new_node)
        return new_node

    def insert_before(self, node, data):
        if node is self._head:
            raise ValueError("cannot insert before the head sentinel")
        new_node = Node(data)
        self._link_between(node.prev, node, new_node)
        return new_node

    def remove_front(self):
        if self.is_empty():
            return None
        return self.remove_node(self._head.next)

    def remove_back(self):
        if self.is_empty():
            return None
        return self.remove_node(self._tail.prev)

    def remove_node(self, node):
        if node is None or not node._linked:
            return None
        node.prev.next = node.next
        node.next.prev = node.prev
        node.prev = None
        node.next = None
        node._linked = False
        self._size -= 1
        return node

    def move_to_front(self, node):
        if node is None or not node._linked:
            return
        if node is self._head.next:
            return
        previous = node.prev
        following = node.next
        previous.next = following
        following.prev = previous
        first = self._head.next
        self._head.next = node
        node.prev = self._head
        node.next = first
        first.prev = node

    def peek_front(self):
        return None if self.is_empty() else self._head.next

    def peek_back(self):
        return None if self.is_empty() else self._tail.prev

    def is_empty(self):
        return self._size == 0

    def size(self):
        return self._size

    def __iter__(self):
        node = self._head.next
        while node is not self._tail:
            yield node.data
            node = node.next

    def to_list(self):
        result = []
        for data in self:
            result.append(data)
        return result

    def _link_between(self, previous, following, node):
        node.prev = previous
        node.next = following
        node._linked = True
        previous.next = node
        following.prev = node
        self._size += 1
