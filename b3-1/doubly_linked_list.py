"""LRU 순서와 해시 버킷 체이닝에 사용하는 이중 연결 리스트다."""


class Node:
    """prev, next, data 필드를 갖는 이중 연결 리스트 노드다."""

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
    """센티넬 노드로 O(1) 구조 변경을 보장하는 이중 연결 리스트다."""

    def __init__(self):
        # 양 끝 센티넬을 두면 빈 리스트도 삽입·삭제 로직이 동일해진다.
        self._head = Node()
        self._tail = Node()
        self._head.next = self._tail
        self._tail.prev = self._head
        self._size = 0

    def insert_front(self, data):
        """데이터를 맨 앞에 삽입하고 새 노드를 반환한다."""
        return self.insert_after(self._head, data)

    def insert_back(self, data):
        """데이터를 맨 뒤에 삽입하고 새 노드를 반환한다."""
        return self.insert_before(self._tail, data)

    def insert_after(self, node, data):
        """기준 노드 뒤에 데이터를 삽입한다."""
        if node is self._tail:
            raise ValueError("cannot insert after the tail sentinel")
        new_node = Node(data)
        self._link_between(node, node.next, new_node)
        return new_node

    def insert_before(self, node, data):
        """기준 노드 앞에 데이터를 삽입한다."""
        if node is self._head:
            raise ValueError("cannot insert before the head sentinel")
        new_node = Node(data)
        self._link_between(node.prev, node, new_node)
        return new_node

    def remove_front(self):
        """맨 앞 노드를 제거해 반환한다."""
        if self.is_empty():
            return None
        return self.remove_node(self._head.next)

    def remove_back(self):
        """맨 뒤 노드를 제거해 반환한다."""
        if self.is_empty():
            return None
        return self.remove_node(self._tail.prev)

    def remove_node(self, node):
        """연결된 특정 노드를 O(1)에 제거한다."""
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
        """연결된 특정 노드를 O(1)에 맨 앞으로 이동한다."""
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
        """맨 앞 노드를 제거하지 않고 반환한다."""
        return None if self.is_empty() else self._head.next

    def peek_back(self):
        """맨 뒤 노드를 제거하지 않고 반환한다."""
        return None if self.is_empty() else self._tail.prev

    def is_empty(self):
        """리스트가 비어 있는지 반환한다."""
        return self._size == 0

    def size(self):
        """저장된 노드 수를 반환한다."""
        return self._size

    def __iter__(self):
        node = self._head.next
        while node is not self._tail:
            yield node.data
            node = node.next

    def to_list(self):
        """표시와 테스트용으로 데이터 목록을 반환한다."""
        result = []
        for data in self:
            result.append(data)
        return result

    def _link_between(self, previous, following, node):
        """두 인접 노드 사이에 새 노드를 연결한다."""
        node.prev = previous
        node.next = following
        node._linked = True
        previous.next = node
        following.prev = node
        self._size += 1
