# Mini Redis (b3-1)

Python 3.8+로 구현한 CLI 기반 Mini Redis입니다. String 타입 명령어와 LRU 메모리 제한, TTL 만료 관리를 제공하며, 핵심 저장 구조는 내장 `dict`/`set` 없이 직접 구현했습니다.

## 실행

```bash
python3 main.py
```

종료 명령은 `exit` 또는 `quit`입니다. 값에 공백이 포함되면 큰따옴표로 감쌀 수 있습니다.

```text
mini-redis> CONFIG SET maxmemory 30
OK
mini-redis> SET user:1 "Alice"
OK
mini-redis> GET user:1
"Alice"
mini-redis> EXPIRE user:1 10
(integer) 1
mini-redis> TTL user:1
(integer) 9
```

## 명령어

`SET`, `GET`, `DEL`, `EXISTS`, `DBSIZE`, `KEYS`, `CONFIG SET maxmemory`, `INFO memory`, `EXPIRE`, `TTL`을 지원합니다.

`used_memory`는 UTF-8로 인코딩한 키와 값의 바이트 길이 합계입니다. `maxmemory`가 0이면 무제한이며, 제한을 넘으면 LRU 리스트의 가장 오래된 키부터 제거합니다. 단일 키-값 엔트리 자체가 제한보다 크면 OOM 오류를 반환하고 저장하지 않습니다.

## 자료구조

- `dynamic_array.py`: 용량 2배 확장 동적 배열
- `doubly_linked_list.py`: 센티넬 노드 기반 O(1) 이중 연결 리스트
- `hash_map.py`: 체이닝과 로드 팩터 0.75 기준 리해시를 사용하는 해시맵
- `min_heap.py`: TTL 만료 시각을 빠르게 찾기 위한 최소 힙
- `mini_redis.py`: 위 자료구조를 조합한 명령 실행기

TTL 힙은 덮어쓰기와 재설정으로 생긴 이전 레코드를 버전으로 판별하는 lazy deletion 방식을 사용합니다.

## 테스트

```bash
python3 -m unittest discover -s tests -v
```
