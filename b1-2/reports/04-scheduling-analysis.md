# [Analysis] 앱 작업 로그의 순환 실행 패턴 (보너스)

## 1. 관측 환경 및 증거

`MEMORY_LIMIT=512`, `CPU_MAX_OCCUPY=10`, `MULTI_THREAD_ENABLE=false`.
원본: [app.log](../evidence/scheduling/app.log) · [monitor.log](../evidence/scheduling/monitor.log) · [run.log](../evidence/scheduling/run.log) · [threads_snapshot.txt](../evidence/scheduling/threads_snapshot.txt)

## 2. 로그 발췌

```text
2026-10-16 17:06:03,182 [INFO] >>> Scenario Selected: [Healthy System Monitoring]
2026-10-16 17:06:03,184 [INFO] [Scheduler] Task Scheduler Initialized.
2026-10-16 17:06:03,185 [INFO] [Scheduler] Registered Tasks: ['Thread-A', 'Thread-B', 'Thread-C']
2026-10-16 17:06:03,185 [INFO] [Scheduler] Starting task execution...
2026-10-16 17:06:03,185 [INFO] [Thread-A] Task Started. Calculating... (20%)
2026-10-16 17:06:03,239 [INFO] [Thread-A] Calculating... (40%)
2026-10-16 17:06:03,293 [INFO] [Thread-A] Calculating... (60%)
2026-10-16 17:06:03,347 [INFO] [Thread-A] Calculating... (80%)
2026-10-16 17:06:03,402 [INFO] [Thread-A] Task Completed. (100%)
2026-10-16 17:06:03,458 [INFO] [Thread-B] Task Started. Calculating... (20%)
2026-10-16 17:06:03,510 [INFO] [Thread-B] Calculating... (40%)
2026-10-16 17:06:03,563 [INFO] [Thread-B] Calculating... (60%)
2026-10-16 17:06:03,618 [INFO] [Thread-B] Calculating... (80%)
2026-10-16 17:06:03,674 [INFO] [Thread-B] Task Completed. (100%)
2026-10-16 17:06:03,730 [INFO] [Thread-C] Task Started. Calculating... (20%)
2026-10-16 17:06:03,782 [INFO] [Thread-C] Calculating... (40%)
2026-10-16 17:06:03,838 [INFO] [Thread-C] Calculating... (60%)
2026-10-16 17:06:03,893 [INFO] [Thread-C] Calculating... (80%)
2026-10-16 17:06:03,949 [INFO] [Thread-C] Task Completed. (100%)
2026-10-16 17:06:04,004 [INFO] [Scheduler] All tasks completed.
```

## 3. 해석과 한계

A→B→C가 40%, 80%, 100% 진행 구간을 번갈아 수행하는 패턴은 앱 수준의
Round-Robin 방식과 부합한다. 20%는 작업 진행률이며 OS 시간 퀀텀의 길이가 아니다.
앱의 `Preempted` 문구만으로 커널의 선점이나 실제 OS 스케줄링 정책을 확정할 수 없다.
우선순위·스케줄링 정책의 확인에는 별도의 OS 정책 조회가 필요하다.

일반적으로 Round-Robin은 순환 기회를 부여해 작업 간 공평성과 응답성을 얻을 수 있다.
퀀텀이 짧으면 전환 비용이 커질 수 있다. 이 앱 로그만으로 실제 전환 비용이나
어떤 서비스가 최적일지 판단할 수는 없다.
