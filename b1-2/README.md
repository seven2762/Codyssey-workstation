# b1-2 — 시스템 장애 분석 및 이슈 리포트

빌드된 프로그램(`agent-leak-app`)을 운영 환경(OrbStack Ubuntu VM)에서 실행하며
발생하는 3대 시스템 장애(**Memory Leak/OOM, CPU Spike, Deadlock**)를 관제 데이터와
로그로 진단하고, GitHub Issue 형태의 기술 리포트로 남긴 결과물이다.

## 최종 결과물 (리포트)

| # | 장애 유형 | 리포트 | 트리거 환경변수 | 종료 방식 |
| --- | --- | --- | --- | --- |
| 1 | Memory Leak / OOM | [`reports/01-oom-memory-leak.md`](reports/01-oom-memory-leak.md) | `MEMORY_LIMIT` (경고 범위) | SIGKILL(137) 자가 종료 |
| 2 | CPU Spike | [`reports/02-cpu-spike.md`](reports/02-cpu-spike.md) | `CPU_MAX_OCCUPY > 50` | SIGTERM(143) Watchdog |
| 3 | Deadlock | [`reports/03-deadlock.md`](reports/03-deadlock.md) | `MULTI_THREAD_ENABLE=true` | 무응답(PID 생존) |
| ★ | (보너스) 스케줄링 추론 | [`reports/04-scheduling-analysis.md`](reports/04-scheduling-analysis.md) | 모두 최적(Healthy) | Round-Robin |

각 리포트는 요구 템플릿(**1. Description / 2. Evidence & Logs / 3. Root Cause Analysis
/ 4. Workaround & Verification**)을 따르며, Before & After 비교를 포함한다.

## 도구 (스크립트)

| 파일 | 역할 |
| --- | --- |
| [`monitor.sh`](monitor.sh) | 대상 프로세스의 CPU(/proc 순간값)·RSS·스레드 상태·WCHAN을 주기 샘플링하는 관제 스크립트 |
| [`run-scenario.sh`](run-scenario.sh) | 앱 + monitor.sh를 동시에 구동하여 시나리오별 증거(app.log·monitor.log·threads_snapshot)를 자동 수집하는 오케스트레이터 |

## 증거 자료 (`evidence/`)

```
evidence/
├── oom_before/    MEMORY_LIMIT=128  → 강제 종료(SIGKILL)
├── oom_after/     MEMORY_LIMIT=512  → 캐시 플러시 후 복구/생존
├── cpu_before/    CPU_MAX_OCCUPY=90 → 임계 초과 → SIGTERM
├── cpu_after/     CPU_MAX_OCCUPY=40 → 임계 이하 → 생존
├── deadlock/      MULTI_THREAD=true → 순환 대기 무응답(futex_wait)
└── scheduling/    Healthy 모드       → Round-Robin 라운드로빈
```

각 폴더에는 `app.log`(앱 실행 로그), `monitor.log`(관제 로그), 필요 시
`threads_snapshot.txt`(무응답 시점 스레드 뷰)가 들어 있다.

## 실행 환경 및 재현

- **호스트**: macOS + OrbStack
- **게스트 VM**: `orb create --arch amd64 ubuntu:noble b1-2-agent`
- **실행 계정**: `agent` (uid=1000, 비루트) — 부트 시퀀스 요건
- **필수 환경변수**: `AGENT_HOME`, `AGENT_PORT=15034`, `AGENT_UPLOAD_DIR`,
  `AGENT_KEY_PATH`, `AGENT_LOG_DIR`, `MEMORY_LIMIT`(50–512), `CPU_MAX_OCCUPY`(10–100),
  `MULTI_THREAD_ENABLE`, `api_keys/secret.key`(내용 `agent_api_key_test`)

```bash
# VM 안 agent 계정에서 전체 시나리오 재현
cd /home/agent/agent-app
bin/run-scenario.sh oom_before 128 50 false 40
bin/run-scenario.sh oom_after  512 50 false 75
bin/run-scenario.sh cpu_before 512 90 false 50
bin/run-scenario.sh cpu_after  512 40 false 45
bin/run-scenario.sh deadlock   512 50 true  35
bin/run-scenario.sh scheduling 512 10 false 35
```

## 시나리오 선택 로직 (역추론 요약)

| 조건 | 선택되는 시나리오 |
| --- | --- |
| `MULTI_THREAD_ENABLE=true` | **Deadlock** (동시성 순환 대기) |
| `MEMORY_LIMIT` 경고 범위(≤256) | **OOM** (MemoryGuard 강제 종료) |
| `CPU_MAX_OCCUPY > 50%` | **CPU Spike** (Watchdog SIGTERM) |
| 모두 최적(메모리 안전 + CPU≤50 + 단일 스레드) | **Healthy** (Round-Robin 스케줄러) |
