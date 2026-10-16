# [Bug] Memory Leak / OOM - 메모리 증가 후 MemoryGuard 자가 종료

> 환경: OrbStack Ubuntu 24.04, Linux amd64 / 비루트 `agent`(uid=1000) / 포트 15034
> 실행 시작(UTC): Before `2026-10-16T08:01:48Z`, After `2026-10-16T08:02:08Z`
> 앱·관제 로그 시각은 게스트 현지 시각이며 `run.log`의 `Z` 시각은 UTC다.
> Before: [app.log](../evidence/oom_before/app.log) · [monitor.log](../evidence/oom_before/monitor.log) · [run.log](../evidence/oom_before/run.log) · [threads_snapshot.txt](../evidence/oom_before/threads_snapshot.txt)
> After: [app.log](../evidence/oom_after/app.log) · [monitor.log](../evidence/oom_after/monitor.log) · [run.log](../evidence/oom_after/run.log) · [threads_snapshot.txt](../evidence/oom_after/threads_snapshot.txt)

## 1. Description (현상 설명)

`MEMORY_LIMIT=128`, `CPU_MAX_OCCUPY=50`, `MULTI_THREAD_ENABLE=false`에서
RSS가 시간에 따라 증가하고 `Memory limit exceeded`와 `Self-terminating process`를
남긴 뒤 프로세스가 사라졌다. 로그에 기록된 애플리케이션 보호 정책에 따른 종료이며,
커널 OOM Killer가 종료했다고 판정하지 않는다.

```bash
# VM 내 agent 계정에서 실행, 필수 경로·키는 setup-agent-env.sh로 구성
cd /home/agent/agent-app
bin/run-scenario.sh oom_before 128 50 false 40
bin/run-scenario.sh oom_after 512 50 false 75
```

## 2. Evidence & Logs (증거 자료)

Before 프로그램 로그(원본 발췌):

```text
2026-10-16 17:01:50,250 [INFO] [MemoryWorker] Current Heap: 25MB
2026-10-16 17:01:53,270 [INFO] [MemoryWorker] Current Heap: 50MB
2026-10-16 17:01:56,293 [INFO] [MemoryWorker] Current Heap: 75MB
2026-10-16 17:01:59,318 [INFO] [MemoryWorker] Current Heap: 100MB
2026-10-16 17:02:02,342 [INFO] [MemoryWorker] Current Heap: 125MB
2026-10-16 17:02:05,366 [INFO] [MemoryWorker] Current Heap: 150MB
2026-10-16 17:02:05,366 [CRITICAL] [MemoryGuard] Memory limit exceeded (150MB >= 128MB) / (Recommend Over 256MB)
2026-10-16 17:02:05,366 [CRITICAL] [MemoryGuard] Self-terminating process 4461 to prevent system instability.
```

Before `monitor.sh`의 OS 관제 행. 열은 시각 / PID / STAT / %CPU / RSS(MB) / 스레드 / 경과다.

```text
2026-10-16 17:01:48.539   | 4461   | SN   | -      | 25       | 1       | 0s
2026-10-16 17:01:51.052   | 4461   | SN   | 0.0    | 50       | 1       | 2s
2026-10-16 17:01:53.562   | 4461   | SN   | 0.0    | 75       | 1       | 5s
2026-10-16 17:01:56.063   | 4461   | SN   | 0.0    | 75       | 1       | 7s
2026-10-16 17:01:58.559   | 4461   | SN   | 0.0    | 100      | 1       | 10s
2026-10-16 17:02:01.069   | 4461   | SN   | 0.0    | 125      | 1       | 12s
2026-10-16 17:02:03.571   | 4461   | SN   | 0.8    | 150      | 1       | 15s
2026-10-16 17:02:04.827   | 4461   | SN   | 0.0    | 150      | 1       | 16s
```

RSS는 25→150MB로 증가했다. `run.log`:

```text
label=oom_before
started_at=2026-10-16T08:01:48Z
MEMORY_LIMIT=128
CPU_MAX_OCCUPY=50
MULTI_THREAD_ENABLE=false
max_seconds=40
launcher_pid=4451
monitor_pid=4454
timed_out=false
app_exit_code=137
monitor_exit_code=0
elapsed_seconds=17
completed_at=2026-10-16T08:02:08Z
```

## 3. Root Cause Analysis (원인 분석)

- 관측 사실: `Current Heap`와 OS RSS가 증가하고, 임계 초과·자가 종료 로그 직후
  `timed_out=false`, 종료 코드 137이 기록됐다. 이는 SIGKILL(128+9) 종료와 부합한다.
- 추론: 워크로드가 메모리를 계속 보유·할당하는 누수성 패턴으로 판단한다. 객체 참조,
  GC 회수 실패, 감시 스레드 구현 등 내부 원인은 소스/메모리 분석 없이 확정할 수 없다.
- OS 원리: RSS는 물리 메모리에 상주하는 페이지 양이다. 가용 메모리가 부족해지면
  회수·스왑 등으로 지연이 발생할 수 있다. 이 실행에서는 커널 OOM 로그를 수집하지
  않았고 앱의 MemoryGuard 로그가 있어 앱 자체 보호 종료로 해석한다.
- SIGKILL은 정리 핸들러를 실행할 수 없는 강제 종료다. 정상적인 정리 완료로 표현하지 않는다.

## 4. Workaround & Verification (조치 및 검증)

`MEMORY_LIMIT`만 128→512MB로 변경했다. After에서는 Healthy 시나리오로 전환되고
메모리 한계 도달 시 캐시 정리·복구 로그가 나타났다. 단순히 한계만 늘려 같은 누수를
늦춘 결과로 일반화하지 않는다. 이 앱의 설정에 따른 실행 경로 변경도 함께 관측됐다.

```text
2026-10-16 17:02:11,582 [INFO] [MemoryWorker] Current Heap: 25MB
2026-10-16 17:03:09,019 [INFO] [MemoryWorker] Current Heap: 500MB
2026-10-16 17:03:12,046 [INFO] [MemoryWorker] Current Heap: 525MB
2026-10-16 17:03:12,047 [WARNING] [MemoryWorker] Memory Usage Reached Limit (525MB). Starting cleanup...
2026-10-16 17:03:12,063 [INFO] [System] Memory Cache Flushed. Process Stabilized.
>>> [SYSTEM] MEMORY RECOVERED (Cache Cleared) <<<
2026-10-16 17:03:17,103 [INFO] [MemoryWorker] Current Heap: 25MB
```

After OS 관측:

```text
2026-10-16 17:02:09.042   | 5017   | SN   | -      | 25       | 1       | 0s
2026-10-16 17:02:23.011   | 5017   | SNl  | 0.0    | 125      | 3       | 14s
2026-10-16 17:02:37.004   | 5017   | SNl  | 3.9    | 250      | 3       | 28s
2026-10-16 17:02:50.988   | 5017   | SNl  | 0.0    | 350      | 3       | 42s
2026-10-16 17:03:04.995   | 5017   | SNl  | 1.6    | 475      | 3       | 56s      [WARNING RSS>=400MB]
2026-10-16 17:03:19.015   | 5017   | SNl  | 0.0    | 50       | 3       | 70s
2026-10-16 17:03:22.832   | 5017   | SNl  | 0.0    | 75       | 3       | 74s
```

| 항목 | Before | After |
| --- | --- | --- |
| MEMORY_LIMIT | 128MB | 512MB |
| 관측 경과 | 17초 | 75초 |
| 앱 종료 코드 | 137 | 143 |
| 관측 종료 후 정리(`timed_out`) | false | true |
| OS RSS 범위 | 25–150MB | 25–525MB |
| 임계 도달 결과 | 자가 종료 | 캐시 정리 후 작업 재개 |

After의 143은 관측 시간 만료 후 실행 스크립트가 보낸 TERM 정리 결과다.
관측 구간 내 복구·생존이 확인됐으며 무기한 안정성을 보장하지 않는다.
근본 해결 제안: 소스 접근이 허용되는 별도 단계에서 보유 객체·캐시 수명과 크기 제한을 점검한다.
