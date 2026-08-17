# [Bug] Deadlock - 두 워커 스레드의 순환 대기(Circular Wait)로 프로세스가 무응답 상태에 빠짐

> 환경: OrbStack Ubuntu 24.04 (noble), amd64 / 실행 계정 `agent`(비루트)
> 대상: `agent-leak-app` (포트 15034)
> 증거 파일: [`evidence/deadlock/`](../evidence/deadlock/)

---

## 1. Description (현상 설명)

- **어떤 현상이 발생했는가?**
  `MULTI_THREAD_ENABLE=true`로 실행하면 두 워커 스레드가 서로 다른 자원을 하나씩
  선점한 뒤 **상대가 쥔 자원을 무한히 기다린다**. 그 결과 프로세스는 **종료되지 않은 채
  (PID 존재) CPU/메모리 변화가 정체되고 로그 기록도 멈춘 무응답 상태**가 된다.
  OOM/CPU 사례처럼 "죽는" 것이 아니라 "**멈춰서 살아있는**" 것이 핵심 차이다.

- **언제, 어떤 조건에서 발생했는가?**
  - `MULTI_THREAD_ENABLE=true` (동시성 모드)
  - 부팅 배너에서 사전 경고가 표시된다:
    ```
    [ THREAD ] Concurrency: True     [ WARNING ]
    >>> SYSTEM WARNING: POTENTIAL DEADLOCK IN CONCURRENT MODE.
    ```

---

## 2. Evidence & Logs (증거 자료)

### 2-1. 프로그램 실행 로그 — 마지막 기록 지점 (`evidence/deadlock/app.log`)

```text
2026-07-07 18:02:46 [WARNING] [System] CAUTION: Strict resource locking is enabled.
2026-07-07 18:02:51 [INFO] [Worker-Thread-1] Attempting to lock [Shared_Memory_A]...
2026-07-07 18:02:51 [INFO] [Worker-Thread-1] LOCK ACQUIRED: [Shared_Memory_A]. (Holding...)
2026-07-07 18:02:51 [INFO] [Worker-Thread-2] Attempting to lock [Socket_Pool_B]...
2026-07-07 18:02:51 [INFO] [Worker-Thread-2] LOCK ACQUIRED: [Socket_Pool_B]. (Holding...)
2026-07-07 18:02:53 [INFO] [Worker-Thread-2] Need resource [Shared_Memory_A] to write logs.
2026-07-07 18:02:53 [INFO] [Worker-Thread-2] WAITING for [Shared_Memory_A]... (Status: BLOCKED)
2026-07-07 18:02:53 [INFO] [Worker-Thread-1] Need resource [Socket_Pool_B] to finish job.
2026-07-07 18:02:53 [INFO] [Worker-Thread-1] WAITING for [Socket_Pool_B]... (Status: BLOCKED)
        ── 이후 로그 완전 정지 (18:02:53 이후 기록 없음) ──
```

핵심: 양쪽 스레드가 **`WAITING ... (Status: BLOCKED)`** 를 남긴 시점(18:02:53)을
**마지막으로 로그가 완전히 멈춘다.** 자원 점유 관계는 다음과 같다.

```
Worker-Thread-1 :  HOLD [Shared_Memory_A]  ──wants──►  [Socket_Pool_B]
Worker-Thread-2 :  HOLD [Socket_Pool_B]    ──wants──►  [Shared_Memory_A]
                    └──────────── 순환 대기 (Circular Wait) ───────────┘
```

### 2-2. PID 존재 + 스레드 락 대기 증거 (`evidence/deadlock/threads_snapshot.txt`)

로그가 멈춘 뒤에도 프로세스는 살아있다. `ps -L`(스레드 뷰)로 관측한 결과:

```text
----- ps -L (thread view) PID=17973 -----   # 부모(런처)
   PID    TID STAT %CPU %MEM WCHAN  CMD
 17973  17973 S    0.1  0.0  do_wai  .../agent-leak-app   # 자식 대기(do_wait)

----- ps -L (thread view) PID=17981 -----   # 실제 워커 프로세스
   PID    TID STAT %CPU %MEM WCHAN  CMD
 17981  17981 SNl  0.3  0.3  futex_  .../agent-leak-app
 17981  18207 SNl  0.0  0.3  futex_  .../agent-leak-app
 17981  18208 SNl  0.0  0.3  futex_  .../agent-leak-app
```

- **PID 17981이 살아있음** = 프로세스가 종료되지 않았다는 직접 증거.
- 세 스레드 모두 **`WCHAN=futex_wait`** = 커널 레벨에서 **futex(뮤텍스/락)를 기다리며
  블록**되어 있다는 결정적 근거. 스레드가 락 대기 상태로 멈춰 있음을 커널이 보고한다.

### 2-3. monitor.sh 관제 로그 — 자원 변화 정체 (`evidence/deadlock/monitor.log`)

```text
TIMESTAMP                 | PID    | STAT | %CPU | RSS(MB) | THREADS | ELAPSED
2026-07-07 18:03:17.907   | 17981  | SNl  | 0.0  | 25      | 3       | 33s
        └ thread TID=17981 STAT=SNl CPU=0.3% WCHAN=futex_wait
        └ thread TID=18207 STAT=SNl CPU=0.0% WCHAN=futex_wait
        └ thread TID=18208 STAT=SNl CPU=0.0% WCHAN=futex_wait
```

`ELAPSED`(경과 시간)만 증가할 뿐 **RSS는 25MB로 고정, %CPU는 ~0%로 정체**된다.
"살아있으나 아무 일도 하지 않는" 무응답 상태를 수치로 입증한다.

---

## 3. Root Cause Analysis (원인 분석)

### 기술적 원인 — 교착상태 4대 조건이 모두 성립
| 조건 | 본 사례에서의 성립 근거 |
| --- | --- |
| **상호 배제**(Mutual Exclusion) | `Shared_Memory_A`, `Socket_Pool_B`는 한 번에 한 스레드만 점유 가능한 배타적 락 |
| **점유 대기**(Hold and Wait) | T1은 A를 쥔 채 B를, T2는 B를 쥔 채 A를 요구 |
| **비선점**(No Preemption) | 어느 스레드도 상대의 락을 강제로 빼앗지 못함 |
| **순환 대기**(Circular Wait) | T1→(B 대기)→T2→(A 대기)→T1 의 원형 의존 사이클 형성 |

네 조건이 동시에 성립하므로 **어느 스레드도 영원히 진행할 수 없다.** 이는
**식사하는 철학자 문제(Dining Philosophers)** 에서 모든 철학자가 왼쪽 포크를 든 채
오른쪽 포크를 기다리는 상황과 정확히 동형이다.

### 관련 OS 동작 원리
- 리눅스 스레드는 뮤텍스 경합 시 **futex(fast userspace mutex)** 를 통해 커널에서
  블록되며, 이때 스레드의 `WCHAN`은 `futex_wait`로 표시된다(2-2 증거와 일치).
- 블록된 스레드는 실행 큐에서 빠져 CPU를 소모하지 않으므로(관제 %CPU≈0), 데드락은
  "폭주"가 아니라 "**정지**"로 나타난다. 그래서 리소스 그래프만 보면 정상처럼 보이고
  **로그 정지 + 스레드 WCHAN**을 함께 봐야 정확히 진단된다.

---

## 4. Workaround & Verification (조치 및 검증)

### 조치: 환경변수 `MULTI_THREAD_ENABLE`로 데드락 재현/회피 비교

```bash
# 재현 (Deadlock 발생)
MULTI_THREAD_ENABLE=true  MEMORY_LIMIT=512 CPU_MAX_OCCUPY=50  ./agent-leak-app
# 회피 (동시성 비활성화)
MULTI_THREAD_ENABLE=false MEMORY_LIMIT=512 CPU_MAX_OCCUPY=50  ./agent-leak-app
```

### Before & After 비교

| 항목 | Before (`MULTI_THREAD_ENABLE=true`) | After (`MULTI_THREAD_ENABLE=false`) |
| --- | --- | --- |
| 부팅 배너 | `POTENTIAL DEADLOCK IN CONCURRENT MODE` | `STARTING WORKLOAD MONITORING` (정상) |
| 실행 흐름 | 두 스레드 순환 대기 → **무응답** | 단일 워크로드 정상 수행 |
| 스레드 상태 | 3개 스레드 `futex_wait`로 정지 | 정상 진행(락 경합 없음) |
| 로그 | `WAITING ... BLOCKED` 이후 **정지** | 지속적으로 기록 |
| 프로세스 | PID 생존하나 **동작 없음**(자연 종료 안 됨) | 정상 동작 |

동시성을 비활성화(`false`)하면 두 스레드가 자원을 두고 경합하는 구조 자체가
사라져 **데드락이 발생하지 않는다.**

### 근본적 해결을 위한 추가 제안 (선택)
`MULTI_THREAD_ENABLE=false`는 동시성을 포기하는 임시 회피책이다. 근본 해결은 아래 중
하나로 **순환 대기 조건을 깨는 것**이다.
- **락 획득 순서 고정(Lock Ordering)**: 모든 스레드가 항상 `A → B` 순서로만 락을
  획득하면 순환이 형성되지 않는다(가장 일반적 해법).
- **타임아웃/`tryLock`**: 일정 시간 내 획득 실패 시 보유 락을 반납하고 재시도(점유 대기 파괴).
- **자원 통합**: 두 자원을 하나의 락으로 묶어 상호 배제 대상을 단일화.

---

### 재현 방법 (Reproducibility)

```bash
cd /home/agent/agent-app
bin/run-scenario.sh deadlock 512 50 true 35
# 무응답 상태에서 스레드 스냅샷이 evidence/deadlock/threads_snapshot.txt 에 자동 저장됨
# 추가 확인:  ps -ef | grep agent-leak-app   /   ps -L -o tid,stat,wchan -p <PID>
```
