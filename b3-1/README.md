# Mini Redis (b3-1)

Python 3.8+로 구현한 CLI 기반 Mini Redis입니다. String 타입 명령어와 LRU 메모리 제한, TTL 만료 관리를 제공하며, 핵심 저장 구조는 내장 `dict`/`set` 없이 직접 구현했습니다.

## 객체지향 구조

각 클래스는 한 가지 책임만 갖도록 분리했습니다.

- `MiniRedis`: REPL이 호출하는 퍼사드. 명령 파싱과 실행 위임만 담당합니다.
- `CommandParser` / `CommandDispatcher`: 입력을 명령 객체로 만들고, 기능별 핸들러로 전달합니다.
- `StringCommandHandler`, `MemoryCommandHandler`, `TtlCommandHandler`: 명령의 인자 검증과 Redis 스타일 응답 생성을 담당합니다.
- `RedisService`: 명령 형식과 분리된 저장·조회·만료 도메인 흐름을 조합합니다.
- `CacheStore`: 해시맵, LRU 리스트, `used_memory`, LRU 제거를 한곳에서 일관되게 관리합니다.
- `TtlManager`: 최소 힙, TTL 버전, lazy deletion을 관리합니다.
- `CacheEntry`, `ExpiryRecord`, `MemoryInfo`: 상태를 표현하는 값 객체입니다.

이 구조 덕분에 CLI 표현, 저장 정책, TTL 정책을 서로 독립적으로 테스트하고 변경할 수 있습니다.

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
- `cache_store.py`: 저장소, LRU, 메모리 제한 관리
- `ttl_manager.py`: TTL 등록과 lazy deletion
- `redis_service.py`: 저장소와 TTL 정책을 조합한 도메인 서비스
- `command_parser.py`, `command_handler.py`: 명령 파싱·기능별 실행·응답 형식화
- `mini_redis.py`: REPL이 사용하는 퍼사드

TTL 힙은 덮어쓰기와 재설정으로 생긴 이전 레코드를 버전으로 판별하는 lazy deletion 방식을 사용합니다.

## 테스트

```bash
python3 -m unittest discover -s tests -v
```
