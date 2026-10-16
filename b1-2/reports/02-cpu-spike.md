# [Bug] CPU Latency - 앱 부하 임계 위반 후 SIGTERM 종료 및 상한 조정

> 환경: OrbStack Ubuntu 24.04, Linux amd64 / 비루트 `agent`(uid=1000) / 포트 15034
> 실행 시작(UTC): Before `2026-10-16T08:03:27Z`, After `2026-10-16T08:03:55Z`
> 앱·관제 로그 시각은 게스트 현지 시각이며 `run.log`의 `Z` 시각은 UTC다.
> Before: [app.log](../evidence/cpu_before/app.log) · [monitor.log](../evidence/cpu_before/monitor.log) · [run.log](../evidence/cpu_before/run.log) · [threads_snapshot.txt](../evidence/cpu_before/threads_snapshot.txt)
> After: [app.log](../evidence/cpu_after/app.log) · [monitor.log](../evidence/cpu_after/monitor.log) · [run.log](../evidence/cpu_after/run.log) · [threads_snapshot.txt](../evidence/cpu_after/threads_snapshot.txt)

## 1. Description (현상 설명)

`MEMORY_LIMIT=512`, `MULTI_THREAD_ENABLE=false`를 고정하고 `CPU_MAX_OCCUPY=90`에서
앱의 `Current Load`가 증가한 뒤 `CPU Threshold Violated!`와 함께 종료됐다.
`CPU_MAX_OCCUPY=40`에서는 cooldown에 도달하고 관측 종료까지 생존했다.

**검증 한계:** 앱 내부 부하 지표의 상승은 확인했으나 OS 실측 CPU 과점유 및 실제 요청
지연은 입증되지 않았다. 이 보고서는 보호 정책 재현 결과이며 CPU 급상승 필수 증거의
완전 충족으로 판정하지 않는다.

```bash
# VM 내 agent 계정에서 실행, 필수 경로·키는 setup-agent-env.sh로 구성
cd /home/agent/agent-app
bin/run-scenario.sh cpu_before 512 90 false 50
bin/run-scenario.sh cpu_after 512 40 false 45
```

## 2. Evidence & Logs (증거 자료)

Before 앱 로그(원본 발췌):

```text
2026-10-16 17:03:30,036 [INFO] [CpuWorker] Started. Maximum CPU Limit: 90%
2026-10-16 17:03:30,038 [INFO] [CpuWorker] Current Load: 5.00%
2026-10-16 17:03:33,167 [INFO] [CpuWorker] Current Load: 14.64%
2026-10-16 17:03:36,297 [INFO] [CpuWorker] Current Load: 20.99%
2026-10-16 17:03:39,422 [INFO] [CpuWorker] Current Load: 26.71%
2026-10-16 17:03:42,546 [INFO] [CpuWorker] Current Load: 35.30%
2026-10-16 17:03:45,672 [INFO] [CpuWorker] Current Load: 41.51%
2026-10-16 17:03:48,799 [INFO] [CpuWorker] Current Load: 48.52%
2026-10-16 17:03:51,930 [INFO] [CpuWorker] Current Load: 55.65%
2026-10-16 17:03:52,031 [CRITICAL] [CpuWorker] CPU Threshold Violated! (55.65%).
```

OS `monitor.sh` 관측(시각 / PID / STAT / %CPU / RSS(MB) / 스레드 / 경과):

```text
2026-10-16 17:03:28.321   | 7191   | SN   | -      | 25       | 1       | 0s
2026-10-16 17:03:33.301   | 7191   | RN   | 1.6    | 25       | 1       | 5s
2026-10-16 17:03:38.286   | 7191   | SN   | 0.0    | 25       | 1       | 10s
2026-10-16 17:03:43.282   | 7191   | SN   | 2.4    | 25       | 1       | 15s
2026-10-16 17:03:48.256   | 7191   | SN   | 0.0    | 25       | 1       | 20s
2026-10-16 17:03:52.017   | 7191   | SN   | 4.0    | 25       | 1       | 23s
```

앱 내부 최고 `Current Load`는 **55.65%**, OS 순간 CPU 최고는
**4%**(1코어=100%)다. 두 지표는 동일하지 않다.
원본 관제의 스레드 행은 `ps -L` 출력 기반이며 프로세스 행의 순간 CPU와 산정 구간도 다르다.

```text
label=cpu_before
started_at=2026-10-16T08:03:27Z
MEMORY_LIMIT=512
CPU_MAX_OCCUPY=90
MULTI_THREAD_ENABLE=false
max_seconds=50
launcher_pid=7181
monitor_pid=7184
timed_out=false
app_exit_code=143
monitor_exit_code=0
elapsed_seconds=24
completed_at=2026-10-16T08:03:55Z
```

원본에는 `CPU Threshold Violated!`가 있으나 명시적인 `WATCHDOG … SIGTERM` 문구는 없다.
로그에 없는 문구를 증거로 추가하지 않았다.

## 3. Root Cause Analysis (원인 분석)

- 관측 사실: 권장 상한 배너는 50%이고, 앱 내부 지표가 50%를 넘은 직후 임계 위반이
  기록됐다. 관측 시간 만료 전(`timed_out=false`) 종료 코드 143(128+15)이 발생했다.
- 추론: 앱의 과점유 방지 정책(미션에서 Watchdog으로 지칭)에 따른 SIGTERM 종료와
  부합한다. 종료 코드는 종료 신호와 부합하는 정보이며 발신 주체, 별도 감시 스레드,
  종료 핸들러 실행·정상 정리 완료를 단독으로 증명하지 않는다.
- OS 원리: 실제 CPU 경합이 발생하면 다른 실행 가능 작업의 대기 시간이 길어져
  응답 지연을 유발할 수 있다. 본 실행에서는 이를 입증할 CPU 급상승·지연 측정이 없다.
- 앱 내부 지표와 OS 실측의 차이는 재현 가능한 관측 사실이다. 내부 지표가 시뮬레이션인지,
  어떤 공식으로 산정되는지는 블랙박스 로그만으로 확정하지 않는다.

## 4. Workaround & Verification (조치 및 검증)

`CPU_MAX_OCCUPY`만 90→40으로 낮췄다. After에서는 Healthy 시나리오로 전환되며,
아래 로그처럼 목표 부하에 도달한 뒤 cooldown으로 내려간다.

```text
2026-10-16 17:03:57,918 [INFO] >>> Scenario Selected: [Healthy System Monitoring]
2026-10-16 17:03:58,742 [INFO] [CpuWorker] Current Load: 5.00%
2026-10-16 17:04:01,869 [INFO] [CpuWorker] Current Load: 12.17%
2026-10-16 17:04:04,996 [INFO] [CpuWorker] Current Load: 20.21%
2026-10-16 17:04:08,122 [INFO] [CpuWorker] Current Load: 22.23%
2026-10-16 17:04:11,247 [INFO] [CpuWorker] Current Load: 27.61%
2026-10-16 17:04:14,375 [INFO] [CpuWorker] Current Load: 29.42%
2026-10-16 17:04:17,503 [INFO] [CpuWorker] Current Load: 31.04%
2026-10-16 17:04:20,632 [INFO] [CpuWorker] Current Load: 32.22%
2026-10-16 17:04:23,763 [INFO] [CpuWorker] Current Load: 37.81%
2026-10-16 17:04:25,881 [INFO] [CpuWorker] Peak reached (40.00%). Starting cooldown...
2026-10-16 17:04:26,891 [INFO] [CpuWorker] Current Load: 40.00%
2026-10-16 17:04:30,014 [INFO] [CpuWorker] Current Load: 32.48%
2026-10-16 17:04:33,142 [INFO] [CpuWorker] Current Load: 29.67%
2026-10-16 17:04:36,268 [INFO] [CpuWorker] Current Load: 27.54%
2026-10-16 17:04:39,397 [INFO] [CpuWorker] Current Load: 22.28%
```

| 항목 | Before | After |
| --- | --- | --- |
| CPU_MAX_OCCUPY | 90% | 40% |
| 관측 경과 | 24초 | 45초 |
| 앱 종료 코드 | 143 | 143 |
| 관측 종료 후 정리(`timed_out`) | false | true |
| 앱 Current Load 최고 | 55.65% | 40.00% |
| OS 순간 CPU 최고 | 4% | 4% |
| 결과 | 임계 위반 후 종료 | cooldown, 관측 구간 생존 |

After의 종료 코드 143은 관측 만료 후 스크립트가 정리한 결과다.

검증: `python3 tests/check_evidence.py`는 보호 정책과 실측을 분리해 확인한다.
`--strict-cpu`는 OS 실측 50% 이상을 추가 요구한다(50%는 이 저장소에서 정한 명시적
판정 기준이며 미션 원문이 정한 수치는 아니다). 기준 미달 시 실패를 유지한다.
다음 단계는 제공자에게 내부 지표 정의·실부하 재현 조건을 확인하는 것이다.
별도 부하 프로그램으로 CPU를 올려 대상 앱의 증거로 대신하지 않는다.

### 독립 OS 관측

별도 명령으로 수집한 [ps -L 원본](../evidence/cpu_before/os_ps.log).
앱 내부 지표와 별개로 대상 워커의 CPU·RSS·대기 상태를 확인했다.

```text
2026-10-16T17:03:29+09:00
Linux b1-2-agent 7.0.14-orbstack-00380-ga7e0a2dc9535 #1 SMP PREEMPT Fri Aug  7 03:48:40 UTC 2026 x86_64 x86_64 x86_64 GNU/Linux
launcher_pid=7181 worker_pid=7191
2026-10-16T17:03:29+09:00
    PID    PPID     TID STAT %CPU %MEM   RSS WCHAN                    CMD
   7191    7181    7191 SN    5.1  0.2 25836 do_select                /home/agent/agent-app/bin/agent-leak-app /home/agent/agent-app/bin/agent-leak-app
2026-10-16T17:03:30+09:00
    PID    PPID     TID STAT %CPU %MEM   RSS WCHAN                    CMD
   7191    7181    7191 SN    1.2  0.2 25980 do_select                /home/agent/agent-app/bin/agent-leak-app /home/agent/agent-app/bin/agent-leak-app
2026-10-16T17:03:51+09:00
    PID    PPID     TID STAT %CPU %MEM   RSS WCHAN                    CMD
   7191    7181    7191 RN    1.2  0.2 25980 -                        /home/agent/agent-app/bin/agent-leak-app /home/agent/agent-app/bin/agent-leak-app
```
