# [Analysis] 로그 패턴 분석을 통한 스케줄링 알고리즘 추론 (보너스)

> 환경: OrbStack Ubuntu 24.04 (noble), amd64 / 실행 계정 `agent`(비루트)
> 대상: `agent-leak-app` 정상(Healthy) 실행 상태
> 증거 파일: [`evidence/scheduling/app.log`](../evidence/scheduling/app.log)

---

## 1. 로그 관찰 개요

`agent-leak-app`은 모든 자원 설정이 최적일 때(`MEMORY_LIMIT=512`, `CPU_MAX_OCCUPY=10`,
`MULTI_THREAD_ENABLE=false`) **`[Healthy System Monitoring]`** 시나리오를 선택하고,
내부 **Task Scheduler**가 세 개의 작업(`Thread-A`, `Thread-B`, `Thread-C`)을 실행한다.
이 워커들의 작업 로그를 수집하여, 런타임이 작업을 처리하는 스케줄링 기법을 역추적했다.

```text
2026-07-07 18:03:24 [INFO] >>> Scenario Selected: [Healthy System Monitoring]
2026-07-07 18:03:24 [INFO] [Scheduler] Task Scheduler Initialized.
2026-07-07 18:03:24 [INFO] [Scheduler] Registered Tasks: ['Thread-A', 'Thread-B', 'Thread-C']
2026-07-07 18:03:24 [INFO] [Scheduler] Starting task execution...
```

---

## 2. 증거 자료

로그의 타임스탬프와 작업 진행률(Progress)을 분석한 결과, **하나의 작업이 완료되기
전에 다른 작업이 끼어드는 선점(Preemption)** 이 규칙적으로 관측되었다.

```text
[ Application Log Snapshot — evidence/scheduling/app.log ]
18:03:24.567 [Thread-A] Task Started. Calculating... (20%)
18:03:24.618 [Thread-A] Calculating... (40%)
18:03:24.673 [Thread-A] Preempted. Progress saved at (40%)   ◄─ A 40%에서 중단
18:03:24.728 [Thread-B] Task Started. Calculating... (20%)
18:03:24.784 [Thread-B] Calculating... (40%)
18:03:24.837 [Thread-B] Preempted. Progress saved at (40%)   ◄─ B 40%에서 중단
18:03:24.891 [Thread-C] Task Started. Calculating... (20%)
18:03:24.942 [Thread-C] Calculating... (40%)
18:03:24.996 [Thread-C] Preempted. Progress saved at (40%)   ◄─ C 40%에서 중단
18:03:25.049 [Thread-A] Resumed. Calculating... (60%)        ◄─ A 재개(40%→)
18:03:25.106 [Thread-A] Calculating... (80%)
18:03:25.162 [Thread-A] Preempted. Progress saved at (80%)
18:03:25.218 [Thread-B] Resumed. Calculating... (60%)
18:03:25.271 [Thread-B] Calculating... (80%)
18:03:25.323 [Thread-B] Preempted. Progress saved at (80%)
18:03:25.377 [Thread-C] Resumed. Calculating... (60%)
18:03:25.480 [Thread-C] Preempted. Progress saved at (80%)
18:03:25.532 [Thread-A] Resumed. Calculating... (100%)
18:03:25.584 [Thread-B] Resumed. Calculating... (100%)
18:03:25.634 [Thread-C] Resumed. Calculating... (100%)
18:03:25.688 [Scheduler] All tasks completed.
```

### 관측된 정량적 패턴
- **고정 시간 할당량(Time Quantum)**: 각 작업은 한 번 실행될 때마다 항상 **정확히 20%씩**
  진행하고 선점된다(20→40 실행 후 중단, 다음 턴에 60→80). 균일한 퀀텀 단위.
- **공평한 순환(Round rotation)**: 실행 순서가 **A → B → C → A → B → C → …** 로 일정하게
  반복된다. 특정 작업이 연속으로 CPU를 독점하지 않는다.
- **선점형(Preemptive)**: `Preempted. Progress saved` → `Resumed` 로그가, 작업이 100%
  완료 전에 강제로 교체되고 나중에 진행률을 이어받아 재개됨을 보여준다.

---

## 3. 패턴 분석 및 결론

- **순차 처리(FCFS) 아님**: `Thread-A`가 100% 완료되기 전에 40%에서 `Preempted`되고
  `Thread-B`가 실행되었으므로, 먼저 온 작업을 끝까지 처리하는 First-Come-First-Served가
  아니다.
- **우선순위(Priority) 아님**: 특정 스레드가 자원을 독점하거나 먼저 완료되는 경향 없이
  A, B, C가 **동일한 20% 퀀텀**으로 공평하게 번갈아 진행된다. 우선순위 편향이 없다.
- **최종 결론**: 각 작업이 **정해진 시간 할당량(20% 상당의 퀀텀)만큼만 CPU를 사용하고
  선점되어 큐의 맨 뒤로 돌아가는** 방식이므로, 적용된 스케줄링 기법은
  **라운드 로빈(Round-Robin)** 으로 추론된다.

---

## 4. 알고리즘 장단점 및 적합 아키텍처 분석

### Round-Robin의 장단점
| 구분 | 내용 |
| --- | --- |
| **장점** | ① 모든 작업에 공평하게 CPU를 분배(기아 상태 없음) ② 짧은 응답 시간 — 새 작업이 최대 (n-1)×퀀텀 안에 실행 시작 ③ 구현이 단순하고 예측 가능 |
| **단점** | ① 잦은 컨텍스트 스위칭으로 인한 오버헤드(퀀텀이 너무 작을 때) ② 처리량(throughput) 관점에서는 비효율 — 긴 작업이 여러 번 쪼개져 총 완료 시간이 늘어남 ③ 퀀텀 크기 선정이 성능을 크게 좌우 |

### 적합한 서비스 성격
- **적합**: **실시간 응답성이 중요한 대화형/멀티유저 서비스**. 예를 들어 다수 클라이언트
  요청을 다루는 **웹 서버·API 게이트웨이**, 여러 세션을 동시에 처리해야 하는 **채팅/스트리밍
  백엔드**처럼, "한 요청이 다른 요청을 오래 굶기지 않는 공평성"이 핵심인 워크로드.
  본 앱이 다수 워커를 공평 순환시키는 것은 이런 응답성 우선 설계와 부합한다.
- **부적합**: **처리량이 최우선인 대용량 배치/일괄 연산 서버**. 야간 ETL, 대규모 렌더링,
  과학 연산처럼 "총 완료 시간·throughput"이 중요한 경우에는, 잦은 선점 오버헤드가
  손해이며 **FCFS나 SJF(최단 작업 우선)** 계열이 더 유리하다.

### 요약
> 관측된 로그의 **고정 퀀텀(20%) · 공평 순환(A→B→C) · 선점(Preempt/Resume)** 세 가지
> 특징은 Round-Robin의 정의적 속성과 일치한다. 이 알고리즘은 응답성·공평성이 중요한
> 대화형 서비스에 적합하고, 순수 처리량이 중요한 배치 워크로드에는 상대적으로 불리하다.
