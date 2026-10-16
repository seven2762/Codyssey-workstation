# b1-2 — 시스템 장애 분석 및 이슈 리포트

빌드된 프로그램(`agent-leak-app`)을 운영 환경(OrbStack Ubuntu VM)에서 실행하며
발생하는 3대 시스템 장애(**Memory Leak/OOM, CPU Spike, Deadlock**)를 관제 데이터와
로그로 진단하고, GitHub Issue 형태의 기술 리포트로 남긴 결과물이다.

## 한 번에 VM 생성·재현·검증하기

`agent-leak-app-x86`은 Linux x86_64 바이너리다. macOS 호스트에서 다음 한 줄을
실행하면 `amd64` OrbStack Ubuntu VM을 생성하고, 실행 환경을 프로비저닝한 뒤 7개
Before/After 시나리오를 실행하고, 결과를 검증해 이 저장소의 `evidence/`로 가져온다.
프로비저닝 파일은 표준입력으로 VM의 임시 디렉터리에 전송하므로 macOS Desktop 공유
마운트 접근 여부에 의존하지 않는다.

```bash
./orbstack-machine.sh demo
```

처음부터 깨끗한 VM으로 시연하려면 다음 명령을 사용한다. 이 명령은
`MACHINE_NAME`으로 지정한 미션 전용 VM만 삭제한다.

```bash
./orbstack-machine.sh reset-demo
```

기본 VM 이름은 `b1-2-agent`이며 환경변수로 바꿀 수 있다.

```bash
MACHINE_NAME=b1-2-demo ./orbstack-machine.sh demo
```

전체 재현은 약 5분이 걸린다. VM 생성·패키지 설치 시간은 별도다.

### 단계별 실행

```bash
./orbstack-machine.sh create      # amd64 Ubuntu machine 생성
./orbstack-machine.sh provision   # agent(uid=1000) 및 실행 환경 구성
./orbstack-machine.sh run-all     # 7개 시나리오 실행 + 결과 판정
./orbstack-machine.sh verify      # VM 구성 + 증거 재검증
./orbstack-machine.sh collect     # VM의 evidence를 저장소로 복사
./orbstack-machine.sh shell       # VM 셸 접속
./orbstack-machine.sh stop
```

`provision`, `run-all`, `verify`, `collect`는 기존 VM이 없으면 먼저 생성·시작한다.
프로비저닝은 같은 VM에서 여러 번 실행해도 안전하며, 기존 API 키 파일은 덮어쓰지 않는다.
`collect`는 실제 재현 결과로 같은 이름의 증거 파일을 갱신하므로 타임스탬프와 PID는
실행할 때마다 달라진다.

## 최종 결과물 (리포트)

최근 실제 재현 수치와 검사 결과, CPU 미충족 항목은
[`reports/validation.md`](reports/validation.md)에 정리했다.

| # | 장애 유형 | 리포트 | 트리거 환경변수 | 종료 방식 |
| --- | --- | --- | --- | --- |
| 1 | Memory Leak / OOM | [`reports/01-oom-memory-leak.md`](reports/01-oom-memory-leak.md) | `MEMORY_LIMIT` (경고 범위) | SIGKILL(137) 자가 종료 |
| 2 | CPU Spike | [`reports/02-cpu-spike.md`](reports/02-cpu-spike.md) | `CPU_MAX_OCCUPY > 50` | SIGTERM(143) Watchdog |
| 3 | Deadlock | [`reports/03-deadlock.md`](reports/03-deadlock.md) | `MULTI_THREAD_ENABLE=true` | 무응답(PID 생존) |
| ★ | (보너스) 스케줄링 추론 | [`reports/04-scheduling-analysis.md`](reports/04-scheduling-analysis.md) | 모두 최적(Healthy) | Round-Robin |

각 리포트는 요구 템플릿(**1. Description / 2. Evidence & Logs / 3. Root Cause Analysis
/ 4. Workaround & Verification**)을 따르며, Before & After 비교를 포함한다.
재사용할 빈 양식은 [`reports/issue-template.md`](reports/issue-template.md)에 있다.

### 증거 해석의 한계

앱의 `Current Load`는 OS의 `%CPU`와 별개다. CPU 정책에 따른 종료/회피를 확인했더라도
OS 실측 급상승이 없으면 미션의 CPU 과점유 증거까지 충족했다고 판정하지 않는다.
종료 코드 143만으로 Watchdog의 주체나 정상 정리 완료를 확정할 수 없으므로,
임계 위반 로그와 `run.log`의 `timed_out=false`를 함께 확인한다.
각 After 실행은 관측 구간의 생존을 입증하며 무기한 안정성을 보장하지 않는다.

## 도구 (스크립트)

| 파일 | 역할 |
| --- | --- |
| [`orbstack-machine.sh`](orbstack-machine.sh) | macOS에서 VM 생성·프로비저닝·전체 실행·검증·증거 회수를 제어하는 진입점 |
| [`provision-orbstack.sh`](provision-orbstack.sh) | VM 내부에 `agent(uid=1000)` 계정과 실행 파일을 멱등 구성 |
| [`setup-agent-env.sh`](setup-agent-env.sh) | 필수 디렉터리·테스트 키·source 가능한 `.env`를 재현 가능하게 생성 |
| [`monitor.sh`](monitor.sh) | 대상 프로세스의 CPU(/proc 순간값)·RSS·스레드 상태·WCHAN을 주기 샘플링하는 관제 스크립트 |
| [`run-scenario.sh`](run-scenario.sh) | 앱 + monitor를 구동하고 `app.log`·`monitor.log`·`threads_snapshot.txt`·`run.log`를 수집 |
| [`run-all-scenarios.sh`](run-all-scenarios.sh) | OOM/CPU/Deadlock Before·After와 Scheduling까지 7개 시나리오를 순서대로 실행 |
| [`verify-results.sh`](verify-results.sh) | 종료 코드, 타임아웃 생존, 장애·복구 로그, futex 증거를 자동 판정 |
| [`verify-orbstack.sh`](verify-orbstack.sh) | VM 아키텍처·계정·권한·실행 파일과 시나리오 증거를 통합 검증 |
| [`tests/test_submission.sh`](tests/test_submission.sh) | VM 없이 셸 계약과 실패 판정 로직을 빠르게 회귀 테스트 |

## 증거 자료 (`evidence/`)

```
evidence/
├── oom_before/    MEMORY_LIMIT=128  → 강제 종료(SIGKILL)
├── oom_after/     MEMORY_LIMIT=512  → 캐시 플러시 후 복구/생존
├── cpu_before/    CPU_MAX_OCCUPY=90 → 임계 초과 → SIGTERM
├── cpu_after/     CPU_MAX_OCCUPY=40 → 임계 이하 → 생존
├── deadlock_before/ MULTI_THREAD=true  → 순환 대기 무응답(futex_wait)
├── deadlock_after/  MULTI_THREAD=false → 락 경합 회피/생존
└── scheduling/    Healthy 모드       → Round-Robin 라운드로빈
```

각 폴더에는 `app.log`(앱 실행 로그), `monitor.log`(관제 로그),
`threads_snapshot.txt`(타임아웃 시점 스레드 뷰), `run.log`(환경변수·종료 코드·실행
시간)가 들어 있다. 기존 수동 재현 자료인 `evidence/deadlock/`은 리포트 인용 호환을
위해 과거 자료로 유지하며, 현재 데드락 리포트는 `deadlock_before/`와 `deadlock_after/`를 인용한다.

## 실행 환경 및 재현

- **호스트**: macOS + OrbStack
- **게스트 VM**: `orb create --arch amd64 ubuntu:noble b1-2-agent`
- **실행 계정**: `agent` (uid=1000, 비루트) — 부트 시퀀스 요건
- **필수 환경변수**: `AGENT_HOME`, `AGENT_PORT=15034`, `AGENT_UPLOAD_DIR`,
  `AGENT_KEY_PATH`, `AGENT_LOG_DIR`, `MEMORY_LIMIT`(50–512), `CPU_MAX_OCCUPY`(10–100),
  `MULTI_THREAD_ENABLE`, `api_keys/secret.key`(내용 `agent_api_key_test`)

VM 안에서 직접 전체 시나리오를 다시 실행할 수도 있다.

```bash
sudo -u agent -H env AGENT_HOME=/home/agent/agent-app \
  /home/agent/agent-app/bin/run-all-scenarios.sh
```

개별 시나리오 실행 형식은 다음과 같다.

```bash
/home/agent/agent-app/bin/run-scenario.sh \
  <label> <MEMORY_LIMIT> <CPU_MAX_OCCUPY> <true|false> <관측시간(초)>
```

## 빠른 로컬 검증

VM을 만들지 않고 셸 문법, 실행 권한, 환경 구성 멱등성, 시나리오 인자, `run.log`,
증거 성공·실패 판정과 저장소에 회수된 실제 증거를 검증한다.

```bash
bash tests/test_submission.sh
python3 tests/check_evidence.py
# OS CPU 실측 50% 이상도 요구하는 추가 판정 (50%는 명시적으로 정한 검증 기준)
python3 tests/check_evidence.py --strict-cpu
```

기본 셸 검증 성공은 앱 시나리오 검증 성공을 의미한다. 정량 검증의 `LIMITATION`과
엄격 CPU 검증 실패도 함께 검토해야 전체 미션 충족 여부를 판단할 수 있다.

## 실행으로 확인한 설정별 동작

| 조건 | 선택되는 시나리오 |
| --- | --- |
| `MEMORY_LIMIT=512`, `CPU_MAX_OCCUPY=50`, `MULTI_THREAD_ENABLE=true` | **Deadlock** (동시성 순환 대기) |
| `MEMORY_LIMIT=128`, `CPU_MAX_OCCUPY=50`, `MULTI_THREAD_ENABLE=false` | **OOM** (MemoryGuard 강제 종료) |
| `MEMORY_LIMIT=512`, `CPU_MAX_OCCUPY=90`, `MULTI_THREAD_ENABLE=false` | **CPU 부하 정책** (임계 위반 로그 후 SIGTERM과 부합하는 종료) |
| `MEMORY_LIMIT=512`, CPU=10/40/50, `MULTI_THREAD_ENABLE=false` | **Healthy** (작업 순환 실행 및 워커 진행) |

위 표는 실행한 조합의 관측 결과다. 미실행 설정의 정확한 분기 경계나 내부 구현까지
확정한 결과가 아니다.
