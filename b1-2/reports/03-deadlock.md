# [Bug] Deadlock - 두 워커의 반대 순서 락 획득으로 순환 대기

> 환경: OrbStack Ubuntu 24.04, Linux amd64 / 비루트 `agent`(uid=1000) / 포트 15034
> 실행 시작(UTC): Before `2026-10-16T08:04:44Z`, After `2026-10-16T08:05:22Z`
> 앱·관제 로그 시각은 게스트 현지 시각이며 `run.log`의 `Z` 시각은 UTC다.
> Before: [app.log](../evidence/deadlock_before/app.log) · [monitor.log](../evidence/deadlock_before/monitor.log) · [run.log](../evidence/deadlock_before/run.log) · [threads_snapshot.txt](../evidence/deadlock_before/threads_snapshot.txt)
> After: [app.log](../evidence/deadlock_after/app.log) · [monitor.log](../evidence/deadlock_after/monitor.log) · [run.log](../evidence/deadlock_after/run.log) · [threads_snapshot.txt](../evidence/deadlock_after/threads_snapshot.txt)

## 1. Description (현상 설명)

`MEMORY_LIMIT=512`, `CPU_MAX_OCCUPY=50`, `MULTI_THREAD_ENABLE=true`에서
각 워커가 자원을 하나씩 점유하고 상대 자원을 기다리는 `BLOCKED` 로그를 남긴 뒤
출력이 멈췄다. PID는 관측 종료까지 존재하며 마지막 관제 구간에서 CPU/RSS가 정체됐다.

```bash
# VM 내 agent 계정에서 실행, 필수 경로·키는 setup-agent-env.sh로 구성
cd /home/agent/agent-app
bin/run-scenario.sh deadlock_before 512 50 true 35
bin/run-scenario.sh deadlock_after 512 50 false 35
```

## 2. Evidence & Logs (증거 자료)

Before 마지막 로그(원본 발췌):

```text
2026-10-16 17:04:46,502 [WARNING] [System] CAUTION: Strict resource locking is enabled.
2026-10-16 17:04:51,531 [INFO] [Worker-Thread-1] Process Started. Attempting to lock [Shared_Memory_A]...
2026-10-16 17:04:51,531 [INFO] [AgentWorker][Worker-Thread-1] LOCK ACQUIRED: [Shared_Memory_A]. (Holding...)
2026-10-16 17:04:51,531 [INFO] [AgentWorker][Worker-Thread-1] Processing critical data in Memory A...
2026-10-16 17:04:51,537 [INFO] [AgentWorker][Worker-Thread-2] Process Started. Attempting to lock [Socket_Pool_B]...
2026-10-16 17:04:51,537 [INFO] [AgentWorker][Worker-Thread-2] LOCK ACQUIRED: [Socket_Pool_B]. (Holding...)
2026-10-16 17:04:51,537 [INFO] [AgentWorker][Worker-Thread-2] Establishing network connections in Pool B...
2026-10-16 17:04:51,537 [INFO] [AgentWorker] Waiting for worker threads to complete transactions...
2026-10-16 17:04:53,542 [INFO] [AgentWorker][Worker-Thread-1] Need resource [Socket_Pool_B] to finish job.
2026-10-16 17:04:53,542 [INFO] [AgentWorker][Worker-Thread-1] WAITING for [Socket_Pool_B]... (Status: BLOCKED)
2026-10-16 17:04:53,552 [INFO] [AgentWorker][Worker-Thread-2] Need resource [Shared_Memory_A] to write logs.
2026-10-16 17:04:53,552 [INFO] [AgentWorker][Worker-Thread-2] WAITING for [Shared_Memory_A]... (Status: BLOCKED)
```

관측 종료 직전 프로세스 트리의 `ps -L` 결과. PID/PPID/TID/STAT/%CPU/%MEM/WCHAN/CMD:

```text
----- process tree @ 2026-10-16 17:05:20 -----
    PID    PPID     TID STAT %CPU %MEM WCHAN  CMD
   9343    9333    9343 SNl   0.2  0.2 futex_ /home/agent/agent-app/bin/agent-leak-app /home/agent/agent-app/bin/agent-leak-app
   9343    9333    9566 SNl   0.0  0.2 futex_ /home/agent/agent-app/bin/agent-leak-app /home/agent/agent-app/bin/agent-leak-app
   9343    9333    9567 SNl   0.0  0.2 futex_ /home/agent/agent-app/bin/agent-leak-app /home/agent/agent-app/bin/agent-leak-app
    PID    PPID     TID STAT %CPU %MEM WCHAN  CMD
   9333    9316    9333 S     0.1  0.0 do_wai /home/agent/agent-app/bin/agent-leak-app /home/agent/agent-app/bin/agent-leak-app
```

PID 존재는 위 프로세스 목록으로 확인된다. `monitor.sh`의 시간에 따른 OS 관측:

```text
2026-10-16 17:04:44.792   | 9343   | SN   | -      | 25       | 1       | 0s
2026-10-16 17:04:51.039   | 9343   | SN   | 0.0    | 25       | 1       | 6s
2026-10-16 17:04:57.391   | 9343   | SNl  | 0.0    | 25       | 3       | 12s
2026-10-16 17:05:03.749   | 9343   | SNl  | 0.0    | 25       | 3       | 19s
2026-10-16 17:05:10.119   | 9343   | SNl  | 0.0    | 25       | 3       | 25s
2026-10-16 17:05:16.482   | 9343   | SNl  | 0.0    | 25       | 3       | 31s
2026-10-16 17:05:19.025   | 9343   | SNl  | 0.0    | 25       | 3       | 34s
```

위 행 뒤의 스레드별 WCHAN 상세는 원본 `monitor.log`에서 확인할 수 있다.
낮은 CPU나 futex 대기만으로는 데드락을 단정할 수 없으며, 양쪽 자원의 소유·대기 로그를
함께 근거로 사용했다.

## 3. Root Cause Analysis (원인 분석)

로그의 자원 관계는 T1이 A를 보유하고 B 대기, T2가 B를 보유하고 A 대기다.
두 워커의 순환 대기와 이후 진행 정지를 근거로 교착상태를 추론한다.

| 교착상태 조건 | 로그에 기반한 해석 |
| --- | --- |
| 상호 배제 | 각 자원에 LOCK ACQUIRED가 기록되고 상대가 기다림 |
| 점유 대기 | A 또는 B를 보유한 채 상대 자원을 요구 |
| 비선점 | 관측 구간에 강제 반납·회수·타임아웃 해제 기록 없음 |
| 순환 대기 | T1→B→T2→A→T1 |

OS는 락을 기다리는 스레드를 잠들게 할 수 있어 CPU가 낮아도 작업이 멈출 수 있다.
`futex` 대기는 이 해석을 뒷받침한다. 락 구현, 무한 대기 보장, 다른 입력에서도 동일한
동작인지는 소스 확인 없이 확정하지 않는다. 식사하는 철학자 문제의 포크 점유·대기와
같은 순환 의존 구조로 이해할 수 있다.

## 4. Workaround & Verification (조치 및 검증)

`MULTI_THREAD_ENABLE`만 true→false로 변경했다. After의 실제 작업 진행 로그:

```text
2026-10-16 17:05:24,835 [INFO] >>> Scenario Selected: [Healthy System Monitoring]
2026-10-16 17:05:25,658 [INFO] [Scheduler] All tasks completed.
2026-10-16 17:05:25,663 [INFO] [MemoryWorker] Current Heap: 25MB
2026-10-16 17:05:25,664 [INFO] [CpuWorker] Current Load: 5.00%
2026-10-16 17:05:28,689 [INFO] [MemoryWorker] Current Heap: 50MB
2026-10-16 17:05:28,795 [INFO] [CpuWorker] Current Load: 7.59%
2026-10-16 17:05:31,717 [INFO] [MemoryWorker] Current Heap: 75MB
2026-10-16 17:05:31,918 [INFO] [CpuWorker] Current Load: 12.13%
2026-10-16 17:05:34,741 [INFO] [MemoryWorker] Current Heap: 100MB
2026-10-16 17:05:35,045 [INFO] [CpuWorker] Current Load: 14.05%
2026-10-16 17:05:37,769 [INFO] [MemoryWorker] Current Heap: 125MB
2026-10-16 17:05:38,176 [INFO] [CpuWorker] Current Load: 20.77%
2026-10-16 17:05:40,788 [INFO] [MemoryWorker] Current Heap: 150MB
2026-10-16 17:05:41,302 [INFO] [CpuWorker] Current Load: 22.02%
2026-10-16 17:05:43,816 [INFO] [MemoryWorker] Current Heap: 175MB
2026-10-16 17:05:44,428 [INFO] [CpuWorker] Current Load: 23.35%
2026-10-16 17:05:46,841 [INFO] [MemoryWorker] Current Heap: 200MB
2026-10-16 17:05:47,555 [INFO] [CpuWorker] Current Load: 30.19%
2026-10-16 17:05:49,861 [INFO] [MemoryWorker] Current Heap: 225MB
2026-10-16 17:05:50,681 [INFO] [CpuWorker] Current Load: 36.90%
2026-10-16 17:05:52,885 [INFO] [MemoryWorker] Current Heap: 250MB
2026-10-16 17:05:53,808 [INFO] [CpuWorker] Current Load: 45.19%
2026-10-16 17:05:55,913 [INFO] [MemoryWorker] Current Heap: 275MB
2026-10-16 17:05:56,939 [INFO] [CpuWorker] Current Load: 49.50%
```

After 관측 종료 직전 스레드 스냅샷:

```text
----- process tree @ 2026-10-16 17:05:58 -----
    PID    PPID     TID STAT %CPU %MEM WCHAN  CMD
  10407   10397   10407 SNl   0.2  2.5 futex_ /home/agent/agent-app/bin/agent-leak-app /home/agent/agent-app/bin/agent-leak-app
  10407   10397   10532 SNl   0.2  2.5 do_sel /home/agent/agent-app/bin/agent-leak-app /home/agent/agent-app/bin/agent-leak-app
  10407   10397   10535 SNl   0.8  2.5 do_sel /home/agent/agent-app/bin/agent-leak-app /home/agent/agent-app/bin/agent-leak-app
    PID    PPID     TID STAT %CPU %MEM WCHAN  CMD
  10397   10380   10397 S     0.1  0.0 do_wai /home/agent/agent-app/bin/agent-leak-app /home/agent/agent-app/bin/agent-leak-app
```

| 항목 | Before | After |
| --- | --- | --- |
| MULTI_THREAD_ENABLE | true | false |
| 관측 경과 | 35초 | 35초 |
| 앱 종료 코드 | 143 | 143 |
| 관측 종료 후 정리(`timed_out`) | true | true |
| 작업 진행 | 양쪽 BLOCKED 후 로그 정지 | Heap/Load 로그 계속 갱신 |
| PID | 존재, 대기 상태 | 존재, 작업 진행 |

두 실행의 143은 모두 관측 만료 후 스크립트의 정리 결과이며 데드락 자연 종료가 아니다.
After는 관측 구간에서 회피가 확인된 것으로 한정한다. 비활성화 설정이 Python/OS의
모든 스레드를 없앤다는 뜻은 아니다.
근본 해결 제안: 모든 워커의 락 획득 순서를 A→B로 통일하거나, 획득 실패 시 보유 락을
반납하는 타임아웃 정책을 검토해 순환 대기를 끊는다.
