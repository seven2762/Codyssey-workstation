# [Bug] CPU Spike - CpuWorker 부하가 안전 임계(50%)를 초과하여 Watchdog이 SIGTERM으로 종료함

> 환경: OrbStack Ubuntu 24.04 (noble), amd64 / 실행 계정 `agent`(비루트)
> 대상: `agent-leak-app` (포트 15034)
> 증거 파일: [`evidence/cpu_before/`](../evidence/cpu_before/) · [`evidence/cpu_after/`](../evidence/cpu_after/)

---

## 1. Description (현상 설명)

- **어떤 현상이 발생했는가?**
  특정 프로세스(`agent-leak-app`)의 `CpuWorker`가 처리 부하를 점진적으로 끌어올린다.
  부하가 애플리케이션의 **안전 임계치(약 50%)** 를 넘어서는 순간, 과점유 방지 정책
  (**Watchdog / CpuWorker Threshold Check**)이 발동하여 프로세스가 종료된다.
  이는 오류(Exception)에 의한 비정상 종료가 아니라 **시스템 보호를 위한 계획된 조치**이다.

- **언제, 어떤 조건에서 발생했는가?**
  - `MULTI_THREAD_ENABLE=false`, `MEMORY_LIMIT=512`(메모리는 안전 범위로 고정하여 변수 격리)
  - `CPU_MAX_OCCUPY`가 안전 임계(50%)를 **초과**하도록 설정된 경우(예: 90)
  - 부팅 배너에서 다음 경고가 표시된다:
    ```
    [ CPU ] Limit: 90%     [ WARNING: Recommend Under 50% ]
    ```

---

## 2. Evidence & Logs (증거 자료)

### 2-1. 프로그램 실행 로그 — CPU 부하 급상승 구간과 종료 (`evidence/cpu_before/app.log`)

```text
2026-07-07 17:55:29 [INFO] [CpuWorker] Started. Maximum CPU Limit: 90%
2026-07-07 17:55:29 [INFO] [CpuWorker] Current Load: 5.00%
2026-07-07 17:55:35 [INFO] [CpuWorker] Current Load: 8.30%
2026-07-07 17:55:38 [INFO] [CpuWorker] Current Load: 16.66%
2026-07-07 17:55:41 [INFO] [CpuWorker] Current Load: 25.12%
2026-07-07 17:55:48 [INFO] [CpuWorker] Current Load: 37.84%
2026-07-07 17:55:54 [INFO] [CpuWorker] Current Load: 43.43%
2026-07-07 17:55:57 [INFO] [CpuWorker] Current Load: 47.59%
2026-07-07 17:56:00 [INFO] [CpuWorker] Current Load: 52.11%
2026-07-07 17:56:00 [CRITICAL] [CpuWorker] CPU Threshold Violated! (52.11%).
```

핵심 로그: **`Current Load`가 5% → 52.11%로 급상승** 후 **`CPU Threshold Violated! (52.11%)`**.
부하가 50%를 넘긴 직후 위반이 선언되었다.

### 2-2. monitor.sh 관제 로그 — 종료 시점 포착 (`evidence/cpu_before/monitor.log`)

```text
TIMESTAMP                 | PID    | STAT | %CPU   | RSS(MB)  | THREADS | ELAPSED
2026-07-07 17:55:30.420   | 13171  | SN   | 0.8    | 25       | 1       | 3s
...
2026-07-07 17:56:00.500   | 13171  | SN   | 0.0    | 25       | 1       | 33s
[monitor.sh] 2026-07-07 17:56:01 PID=13171 프로세스 없음 (종료/소멸 추정). 대기 1/3
[monitor.sh] 2026-07-07 17:56:04 대상 프로세스가 사라졌습니다. 관제를 종료합니다.
```

관제는 프로세스가 살아있다가 **약 33초 시점에 소멸**했음을 포착한다(RSS는 25MB로
일정 → 메모리가 아닌 CPU가 종료 원인임을 교차 확인).

### 2-3. 프로세스 종료 코드

```text
[run-scenario] app exit code: 143 (elapsed 33s)   # 143 = 128 + 15(SIGTERM)
```

종료 코드 **143**은 `SIGTERM(15)`에 의한 종료다. OOM 사례의 `SIGKILL(137)`과 달리,
Watchdog이 **정상 종료 신호(SIGTERM)** 를 보내 우아하게 내렸음을 의미한다.
(내부 `timeout`은 50초였고 실제 종료는 33초이므로, 이는 앱 자체 Watchdog의 종료다.)

### 2-4. 참고 — 앱 내부 부하 지표 vs OS 실측 CPU
`app.log`의 `Current Load`(→52%)는 **앱이 자체 산정하는 논리적 부하 지표**이며,
Watchdog의 종료 판단 기준이다. 반면 `monitor.log`의 `%CPU`(=/proc 델타 기반 OS
실측, 1코어=100%)는 0~4% 수준으로 낮다. 즉 이 앱은 실제 코어를 100% 점유하는 대신
**부하를 내부적으로 모델링**하고, 그 지표로 자기보호를 수행한다. 두 관점을 함께
제시하여 "무엇을 기준으로 종료가 일어났는지"를 명확히 한다.

---

## 3. Root Cause Analysis (원인 분석)

### 기술적 원인
- `CpuWorker`는 시작 시 `CPU_MAX_OCCUPY`를 **목표 상한**으로 삼아 부하를 점진적으로
  끌어올린다.
- 애플리케이션에는 별도의 **고정 안전 임계치(약 50%, 배너의 `Recommend Under 50%`)** 가
  존재한다. `CPU_MAX_OCCUPY`가 이 임계보다 크게 설정되면, 부하가 상승하다 50%를
  통과하는 순간 **Watchdog이 `CPU Threshold Violated`를 선언하고 SIGTERM으로 종료**한다.
- 반대로 `CPU_MAX_OCCUPY`가 임계 이하이면, 부하는 목표치에서 `Peak reached → cooldown`
  으로 진동할 뿐 임계를 넘지 않아 종료가 발생하지 않는다(4장 After 참조).

### 관련 OS 동작 원리
- 한 프로세스가 CPU를 과점유하면, 동일 코어를 공유하는 다른 프로세스의 **스케줄링
  지연(run queue 대기)** 이 커져 시스템 전체 응답성이 저하된다. Watchdog은 이런
  **시스템 지연 유발을 예방**하기 위한 장치다.
- `SIGTERM`은 프로세스가 정리 후 종료할 수 있는 **정상 종료 신호**이고, `SIGKILL`은
  즉시 강제 종료다. 본 사례가 143(SIGTERM)인 점은 "오류가 아닌 통제된 보호 조치"임을
  코드 레벨에서 뒷받침한다.

---

## 4. Workaround & Verification (조치 및 검증)

### 조치: 환경변수 `CPU_MAX_OCCUPY` 하향 (임계 초과 → 임계 이하)

```bash
# Before
CPU_MAX_OCCUPY=90 MEMORY_LIMIT=512 MULTI_THREAD_ENABLE=false  ./agent-leak-app
# After
CPU_MAX_OCCUPY=40 MEMORY_LIMIT=512 MULTI_THREAD_ENABLE=false  ./agent-leak-app
```

### After 결과 — 임계 미달로 종료 없이 생존 (`evidence/cpu_after/app.log`)

```text
2026-07-07 17:56:07 [INFO] [CpuWorker] Started. Maximum CPU Limit: 40%
2026-07-07 17:56:26 [INFO] [CpuWorker] Current Load: 31.59%
2026-07-07 17:56:32 [INFO] [CpuWorker] Current Load: 36.66%
2026-07-07 17:56:34 [INFO] [CpuWorker] Peak reached (40.00%). Starting cooldown...
2026-07-07 17:56:35 [INFO] [CpuWorker] Current Load: 40.00%
2026-07-07 17:56:38 [INFO] [CpuWorker] Current Load: 35.57%
2026-07-07 17:56:41 [INFO] [CpuWorker] Current Load: 27.42%
2026-07-07 17:56:48 [INFO] [CpuWorker] Current Load: 15.52%   # 종료 없이 계속 동작
```

부하가 목표치 40%에서 `Peak reached → cooldown`으로 **진동**하며 50% 임계를 넘지
않는다. 프로세스는 관측 시간 내내 **종료되지 않았다**.

### Before & After 비교

| 항목 | Before (`CPU_MAX_OCCUPY=90`) | After (`CPU_MAX_OCCUPY=40`) |
| --- | --- | --- |
| 부팅 배너 | `WARNING: Recommend Under 50%` | `[ OK ]` |
| 최고 부하 | 52.11% (임계 **초과**) | 40.00% (임계 **이하**) |
| Watchdog | `CPU Threshold Violated!` → 종료 | 미발동 (`cooldown` 반복) |
| 종료 코드 | **143 (SIGTERM)** | 미종료 (생존) |
| 생존 시간 | 약 **33초** | 관측 시간 내내 **지속** |

### 근본적 해결을 위한 추가 제안 (선택)
- 위 조치는 임시 방편이다. 실제 운영에서는 **CpuWorker의 부하 상승 로직 자체를
  프로파일링**하여, 왜 부하가 무한정 상승하는지(작업 폭주/비효율 루프)를 규명해야 한다.
- 상한을 낮추는 것은 처리량을 희생하므로, 근본적으로는 작업을 **비동기 큐/레이트
  리미팅**으로 평탄화하거나 코어를 증설하여 임계 초과 없이 목표 처리량을 확보하는
  방향이 바람직하다.

---

### 재현 방법 (Reproducibility)

```bash
cd /home/agent/agent-app
bin/run-scenario.sh cpu_before 512 90 false 50   # 임계 초과 → SIGTERM
bin/run-scenario.sh cpu_after  512 40 false 45   # 임계 이하 → 생존
```
