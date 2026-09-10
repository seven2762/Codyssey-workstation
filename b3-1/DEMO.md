# Mini Redis 시연 가이드

아래 블록은 모두 실제 실행 결과를 그대로 옮긴 것입니다. `#` 줄은 설명이니 입력하지 마세요.

```bash
python3 main.py
```

각 시나리오는 **새로 실행한 상태**를 전제로 합니다. 앞 시나리오에 이어서 하려면 `exit` 후 다시 실행하세요.

| 시나리오 | 보여주는 것 |
|---|---|
| [A](#a-기본-string-명령어) | String 명령어 6개 |
| [B](#b-메모리-제한과-lru-자동-제거) | maxmemory 초과 시 LRU 축출 (명세 예시) |
| [C](#c-get이-lru-순서를-바꾼다) | 해시맵 + 이중 연결 리스트로 만든 O(1) LRU |
| [D](#d-ttl-만료) | 최소 힙 기반 TTL |
| [E](#e-set-덮어쓰기는-ttl을-초기화한다) | TTL 엣지 케이스 |
| [F](#f-단일-엔트리가-한도를-넘으면-oom) | OOM 처리와 기존 값 보존 |
| [G](#g-에러-처리-표준) | Redis 스타일 에러 4종 |
| [H](#h-used_memory-회계) | used_memory 증감 |

---

## A. 기본 String 명령어

```text
mini-redis> SET user:1 "Alice"
OK
mini-redis> GET user:1
"Alice"
mini-redis> SET user:2 Bob
OK
mini-redis> GET nobody
(nil)
mini-redis> EXISTS user:1
(integer) 1
mini-redis> EXISTS nobody
(integer) 0
mini-redis> DBSIZE
(integer) 2
mini-redis> KEYS
1) "user:1"
2) "user:2"
mini-redis> DEL user:2
(integer) 1
mini-redis> DEL user:2
(integer) 0
mini-redis> DBSIZE
(integer) 1
```

> 값에 공백이 있으면 큰따옴표로 감쌉니다. 없는 키는 `GET` → `(nil)`, `DEL`/`EXISTS` → `(integer) 0`입니다.

---

## B. 메모리 제한과 LRU 자동 제거

과제 명세의 실행 예시를 그대로 재현한 시나리오입니다.

```text
mini-redis> CONFIG SET maxmemory 30
OK
mini-redis> SET user:1 "Alice"
OK
mini-redis> SET user:2 "Bob"
OK
mini-redis> SET user:3 "Charlie"
OK
mini-redis> GET user:1
(nil)
mini-redis> INFO memory
used_memory:22
maxmemory:30
evicted_keys:1
mini-redis> KEYS
1) "user:2"
2) "user:3"
```

**설명 포인트**

- `used_memory`는 UTF-8 바이트 합계입니다. `user:1`(6) + `Alice`(5) = 11, `user:2`+`Bob` = 9, `user:3`+`Charlie` = 13 → 세 개면 33바이트로 30을 넘습니다.
- 그래서 가장 오래 사용되지 않은 `user:1`이 제거되고 9 + 13 = **22**가 남습니다.
- 제거된 키는 `evicted_keys`에 누적됩니다.

---

## C. GET이 LRU 순서를 바꾼다

키·값이 각각 6바이트라 `maxmemory 18`이면 정확히 3개까지만 들어갑니다.

```text
mini-redis> CONFIG SET maxmemory 18
OK
mini-redis> SET k1 aaaa
OK
mini-redis> SET k2 bbbb
OK
mini-redis> SET k3 cccc
OK
mini-redis> GET k1
"aaaa"
mini-redis> SET k4 dddd
OK
mini-redis> KEYS
1) "k3"
2) "k4"
3) "k1"
mini-redis> GET k2
(nil)
mini-redis> INFO memory
used_memory:18
maxmemory:18
evicted_keys:1
```

**설명 포인트**

- `GET k1`이 없었다면 가장 오래된 `k1`이 제거됐을 겁니다. `GET`이 성공하면서 `k1`을 LRU 리스트 맨 앞으로 옮겼기 때문에, 대신 **`k2`가 제거**됐습니다.
- 이 이동이 O(1)인 이유: 해시맵이 키 → `CacheEntry`를 O(1)로 찾아주고, `CacheEntry`가 자기 LRU 노드를 직접 들고 있어서 리스트를 훑지 않고 `move_to_front(node)`로 포인터 4개만 고쳐 끼웁니다.
- 축출은 반대쪽 끝(`peek_back`)에서 꺼내므로 이것도 O(1)입니다.

---

## D. TTL 만료

```text
mini-redis> SET session:1 "token"
OK
mini-redis> TTL session:1
(integer) -1
mini-redis> EXPIRE session:1 3
(integer) 1
mini-redis> TTL session:1
(integer) 2
mini-redis> DBSIZE
(integer) 1
```

여기서 **3초 기다린 뒤** 이어서 입력합니다.

```text
mini-redis> GET session:1
(nil)
mini-redis> TTL session:1
(integer) -2
mini-redis> DBSIZE
(integer) 0
mini-redis> INFO memory
used_memory:0
maxmemory:0
evicted_keys:0
```

**설명 포인트**

- `TTL` 반환값 규칙: `-1`은 만료 시간 없음, `-2`는 키 없음, 0 이상은 남은 초(내림).
- 만료 시각은 `(expire_at, key, version)` 레코드로 **최소 힙**에 들어갑니다. 힙의 루트만 보면 "가장 먼저 만료될 키"를 O(1)에 알 수 있어서, 매번 전체 키를 훑지 않아도 됩니다.
- 만료된 키는 `INFO memory`에서 `used_memory`가 줄지만 **`evicted_keys`는 늘지 않습니다.** 만료와 LRU 축출은 다른 사건이기 때문입니다.

---

## E. SET 덮어쓰기는 TTL을 초기화한다

```text
mini-redis> SET k v
OK
mini-redis> EXPIRE k 100
(integer) 1
mini-redis> TTL k
(integer) 99
mini-redis> SET k v2
OK
mini-redis> TTL k
(integer) -1
mini-redis> EXPIRE nobody 10
(integer) 0
```

**설명 포인트**

- 힙에는 아직 100초짜리 옛 레코드가 남아 있습니다. 하지만 `CacheEntry`의 TTL **버전 번호**가 올라가 있어서, 나중에 힙에서 꺼낸 레코드의 버전이 현재 버전과 다르면 무시합니다(lazy deletion). 힙 중간에서 원소를 찾아 지우는 O(n) 작업을 피하는 방식입니다.
- 없는 키에 `EXPIRE`를 걸면 `(integer) 0`입니다.

---

## F. 단일 엔트리가 한도를 넘으면 OOM

```text
mini-redis> CONFIG SET maxmemory 10
OK
mini-redis> SET k short
OK
mini-redis> GET k
"short"
mini-redis> SET k yyyyyyyyyyyyyyyyyyyy
(error) OOM command not allowed when used_memory > 'maxmemory'
mini-redis> GET k
"short"
mini-redis> INFO memory
used_memory:6
maxmemory:10
evicted_keys:0
```

**설명 포인트**

- 키+값 자체가 `maxmemory`보다 크면 아무리 축출해도 들어갈 수 없으므로, **저장 전에 판단해서** 거부합니다.
- 덮어쓰기가 실패해도 기존 값 `"short"`와 메모리 회계는 그대로입니다.

---

## G. 에러 처리 표준

```text
mini-redis> HELLO
(error) ERR unknown command 'HELLO'
mini-redis> GET
(error) ERR wrong number of arguments for 'GET' command
mini-redis> SET k
(error) ERR wrong number of arguments for 'SET' command
mini-redis> CONFIG SET maxmemory abc
(error) ERR value is not an integer or out of range
mini-redis> EXPIRE k abc
(error) ERR value is not an integer or out of range
mini-redis> SET k "unclosed
(error) ERR syntax error
```

---

## H. used_memory 회계

```text
mini-redis> SET k aaaa
OK
mini-redis> INFO memory
used_memory:5
maxmemory:0
evicted_keys:0
mini-redis> SET k a
OK
mini-redis> INFO memory
used_memory:2
maxmemory:0
evicted_keys:0
mini-redis> DEL k
(integer) 1
mini-redis> INFO memory
used_memory:0
maxmemory:0
evicted_keys:0
```

**설명 포인트**

- 덮어쓸 때 옛 값의 바이트를 먼저 빼고 새 값을 더합니다. `maxmemory:0`은 무제한이라 축출이 일어나지 않습니다.

---

## 종료

`exit` 또는 `quit`을 입력합니다. `Ctrl+C`와 `Ctrl+D`로도 조용히 종료됩니다.

---

## 예상 질문 대비

**Q. 해시 충돌은 어떻게 처리했나요?**
버킷마다 이중 연결 리스트를 두는 체이닝 방식입니다. 해시 함수는 문자 코드를 31진수처럼 누적하고(`hash = hash * 31 + ord(c)`) 상위 비트를 마스킹해 오버플로를 막습니다. 키 1,000개를 넣었을 때 버킷당 체인 길이가 평균 0.49, 최대 4로 고르게 퍼집니다.

**Q. 언제 버킷을 늘리나요?**
`(원소 수 + 1) / 버킷 수`가 0.75를 넘는 순간 버킷을 2배로 늘리고 전체 엔트리를 재배치합니다. 초기 용량 4에서 시작하면 `4 → 8 → 16 → 32` 순으로 커집니다.

**Q. LRU가 왜 O(1)인가요?**
해시맵 단독으로는 "가장 오래된 키"를 알 수 없고, 리스트 단독으로는 키 검색이 O(n)입니다. 둘을 합쳐서 — 해시맵이 키로 엔트리를 찾고, 엔트리가 자기 LRU 노드 포인터를 들고 있어서 — 검색·이동·축출이 모두 O(1)이 됩니다.

**Q. 힙이 TTL에 적합한 이유는?**
필요한 질문이 "지금 만료된 키가 있나?" 하나뿐인데, 최소 힙은 그 답(가장 이른 만료 시각)을 항상 루트에 두기 때문입니다. 확인은 O(1), 제거는 O(log n)입니다.

**Q. `dict`나 `set`을 쓰지 않았다는 걸 어떻게 확인하나요?**
`import`는 `shlex`와 `time` 둘뿐이고, 저장·조회는 전부 직접 구현한 `HashMap`/`DoublyLinkedList`/`MinHeap`을 거칩니다.
