# [Bug] Memory Leak / OOM - MemoryWorker의 무한 힙 증가로 MemoryGuard가 프로세스를 강제 종료함

> 환경: OrbStack Ubuntu 24.04 (noble), amd64 / 실행 계정 `agent`(uid=1000, 비루트)
> 대상: `agent-leak-app` (PyInstaller 패키징 Python 바이너리, 포트 15034)
> 증거 파일: [`evidence/oom_before/`](../evidence/oom_before/) · [`evidence/oom_after/`](../evidence/oom_after/)

---

## 1. Description (현상 설명)

- **어떤 현상이 발생했는가?**
  `agent-leak-app`을 실행하면 내부 `MemoryWorker`가 약 3초 주기로 힙을 25MB씩
  계속 증가시킨다. 사용량이 `MEMORY_LIMIT`에 도달하는 순간, 애플리케이션의
  메모리 보호 정책(**MemoryGuard**)이 발동하여 **예고 없이 프로세스가 강제 종료**된다.
  (관제만 보면 "프로세스가 갑자기 사라진" 것으로 관측된다.)

- **언제, 어떤 조건에서 발생했는가?**
  - `MULTI_THREAD_ENABLE=false` (단일 워크로드 모드)
  - `MEMORY_LIMIT`이 **경고 범위(≤ 256MB, 부팅 배너 `Recommend Over 256MB`)** 로 설정된 경우
  - 부팅 배너에서 다음과 같이 경고가 표시된다:
    ```
    [ MEMORY ] Limit: 128MB     [ WARNING: Recommend Over 256MB ]
    ```

---

## 2. Evidence & Logs (증거 자료)

### 2-1. 프로그램 실행 로그 — 종료 직전/직후 (`evidence/oom_before/app.log`)

```text
2026-07-07 18:01:06 [INFO] [MemoryWorker] Current Heap: 25MB
2026-07-07 18:01:09 [INFO] [MemoryWorker] Current Heap: 50MB
2026-07-07 18:01:12 [INFO] [MemoryWorker] Current Heap: 75MB
2026-07-07 18:01:15 [INFO] [MemoryWorker] Current Heap: 100MB
2026-07-07 18:01:18 [INFO] [MemoryWorker] Current Heap: 125MB
2026-07-07 18:01:21 [INFO] [MemoryWorker] Current Heap: 150MB
2026-07-07 18:01:21 [CRITICAL] [MemoryGuard] Memory limit exceeded (150MB >= 128MB) / (Recommend Over 256MB)
2026-07-07 18:01:21 [CRITICAL] [MemoryGuard] Self-terminating process 15395 to prevent system instability.
```

핵심 로그: **`Memory limit exceeded (150MB >= 128MB)`**, **`Self-terminating process 15395`**

### 2-2. monitor.sh 관제 로그 — 물리 메모리(RSS) 상승 수치 (`evidence/oom_before/monitor.log`)

```text
TIMESTAMP                 | PID    | STAT | %CPU   | RSS(MB)  | THREADS | ELAPSED
2026-07-07 18:01:06.269   | 15395  | SN   | 0.0    | 25       | 1       | 1s
2026-07-07 18:01:07.590   | 15395  | SN   | 1.5    | 50       | 1       | 2s
2026-07-07 18:01:10.262   | 15395  | SN   | 0.7    | 75       | 1       | 5s
2026-07-07 18:01:12.879   | 15395  | SN   | 0.0    | 100      | 1       | 8s
2026-07-07 18:01:16.823   | 15395  | SN   | 0.0    | 125      | 1       | 12s
2026-07-07 18:01:19.450   | 15395  | SN   | 1.5    | 150      | 1       | 14s
[monitor.sh] 2026-07-07 18:01:22 PID=15395 프로세스 없음 (종료/소멸 추정). 대기 1/3
```

`RSS(MB)` 컬럼이 **25 → 50 → 75 → 100 → 125 → 150**으로 단조 증가하다가 프로세스가
사라진다. 앱이 자체 보고한 Heap 수치와 OS가 관측한 RSS가 정확히 일치한다.

### 2-3. 프로세스 종료 코드

```text
[run-scenario] app exit code: 137 (elapsed 17s)   # 137 = 128 + 9(SIGKILL)
```

종료 코드 **137**은 `SIGKILL(9)`에 의한 종료를 의미한다. MemoryGuard가 워커
프로세스를 `kill -9`로 강제 종료했음을 뒷받침한다.

---

## 3. Root Cause Analysis (원인 분석)

### 기술적 원인
- `MemoryWorker`가 참조를 계속 유지하는 객체를 주기적으로 할당하여 **힙이 회수되지
  않고 무한히 증가(전형적 Memory Leak)** 한다. GC가 회수할 수 없는 참조가 계속
  쌓이므로 사용량은 시간에 비례해 우상향한다.
- 애플리케이션은 자체 감시 스레드(**MemoryGuard**)로 현재 사용량과 `MEMORY_LIMIT`을
  비교한다. `사용량 ≥ MEMORY_LIMIT`이 되면, 시스템 전체의 불안정(호스트 OOM Killer
  개입, 스와핑, 동거 프로세스 피해)을 예방하기 위해 **자기 자신을 선제적으로 종료**한다.

### 관련 OS 동작 원리
- 프로세스의 물리 메모리 점유는 `RSS(Resident Set Size)`로 관측되며, 본 관제는
  `ps -o rss`로 이를 수집했다.
- 리눅스는 물리 메모리가 고갈되면 커널의 **OOM Killer**가 `oom_score`가 높은
  프로세스를 강제 종료한다. 본 앱의 MemoryGuard는 이 커널 개입 **이전에** 스스로
  종료하여, 어떤 프로세스가 왜 죽었는지 로그로 남기는 "graceful self-termination"
  전략을 취한다. (로그 없이 커널에 의해 죽는 것보다 원인 추적에 유리하다.)

---

## 4. Workaround & Verification (조치 및 검증)

### 조치: 환경변수 `MEMORY_LIMIT` 상향 (경고 범위 → 안전 범위)

`MEMORY_LIMIT`을 경고 범위(128MB)에서 안전 범위(512MB)로 상향하여 재실행했다.

```bash
# Before
MEMORY_LIMIT=128 CPU_MAX_OCCUPY=50 MULTI_THREAD_ENABLE=false  ./agent-leak-app
# After
MEMORY_LIMIT=512 CPU_MAX_OCCUPY=50 MULTI_THREAD_ENABLE=false  ./agent-leak-app
```

### After 결과 — 강제 종료 대신 "복구"로 전환 (`evidence/oom_after/app.log`)

```text
2026-07-07 18:02:22 [INFO]    [MemoryWorker] Current Heap: 475MB
2026-07-07 18:02:25 [INFO]    [MemoryWorker] Current Heap: 500MB
2026-07-07 18:02:28 [INFO]    [MemoryWorker] Current Heap: 525MB
2026-07-07 18:02:28 [WARNING] [MemoryWorker] Memory Usage Reached Limit (525MB). Starting cleanup...
2026-07-07 18:02:28 [INFO]    [System] Memory Cache Flushed. Process Stabilized.
>>> [SYSTEM] MEMORY RECOVERED (Cache Cleared) <<<
2026-07-07 18:02:33 [INFO]    [MemoryWorker] Current Heap: 25MB      # 힙 리셋 후 재개
```

`evidence/oom_after/monitor.log`의 RSS는 **25 → … → 525 → 25**의 **톱니(sawtooth)
패턴**을 그리며, 프로세스는 관측 시간(75초) 내내 **종료되지 않고 생존**했다.

### Before & After 비교

| 항목 | Before (`MEMORY_LIMIT=128`) | After (`MEMORY_LIMIT=512`) |
| --- | --- | --- |
| 부팅 배너 | `WARNING: Recommend Over 256MB` | `[ OK ]` |
| 한계 도달 시 동작 | MemoryGuard **강제 종료** | 캐시 플러시 후 **복구** |
| 핵심 로그 | `Self-terminating process` | `MEMORY RECOVERED (Cache Cleared)` |
| 종료 코드 | **137 (SIGKILL)** | 미종료 (75s+ 생존, 정리 시 143) |
| 생존 시간 | 약 **17초** | **75초 이상 (지속)** |

### 근본적 해결을 위한 추가 제안 (선택)
- 위 조치는 **임시(Workaround)** 이다. 힙 증가 자체는 여전히 존재하므로, 안전
  범위에서도 사용량이 주기적으로 한계까지 차오른다. 근본 해결은 **MemoryWorker의
  누수 지점(회수되지 않는 참조) 제거**가 필요하다.
- 운영 관점에서는 `MEMORY_LIMIT`을 안전 범위로 두어 즉시 크래시를 막고, 관제
  경고(`RSS ≥ 임계`) 기반 알림을 걸어 누수 추세를 조기에 감지하는 것을 권장한다.

---

### 재현 방법 (Reproducibility)

```bash
# VM(OrbStack) 내 agent 계정에서
cd /home/agent/agent-app
bin/run-scenario.sh oom_before 128 50 false 40   # 강제 종료 재현
bin/run-scenario.sh oom_after  512 50 false 75   # 복구/생존 재현
# 결과: evidence/oom_before/, evidence/oom_after/ 에 app.log · monitor.log 저장
```
