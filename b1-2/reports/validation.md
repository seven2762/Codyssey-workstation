# 미션 검증 결과 — 2026-10-16

실제 OrbStack `b1-2-agent` Ubuntu amd64 VM에서 제공 바이너리를 일반 계정 `agent`로
실행했다. 바이너리 디컴파일·리버스 엔지니어링은 수행하지 않았다.

| 검증 대상 | 관측 결과 | 판정 |
| --- | --- | --- |
| 실행 환경 | uid=1000, 필수 키·디렉터리·권한 부팅 검사 통과, `0.0.0.0:15034` LISTEN | 통과 |
| OOM Before | 128MB 설정, RSS 25→150MB, MemoryGuard 로그 후 17초에 137 종료 | 재현 |
| OOM After | 512MB 설정, RSS 최고 525MB 후 감소·캐시 복구, 75초 관측 | 회피/복구 확인 |
| CPU Before | 상한 90, 앱 Current Load 55.65%에서 위반 로그, 24초에 143 종료 | 정책 재현 |
| CPU After | 상한 40, 40.00%에서 cooldown, 45초 관측 동안 정책 종료 없음 | 정책 회피 확인 |
| CPU OS 실측 | 관제 순간 CPU 최고 4.0%, 별도 `ps -L` 관측도 수집 | 실제 과점유 증거 부족 |
| Deadlock Before | 양쪽 BLOCKED, 동일 PID·RSS 정체·futex 대기, 마지막 로그 26초 뒤에도 관측 | 재현 |
| Deadlock After | 동시성 false, 작업 로그 계속 갱신, 35초 관측 | 구간 내 회피 확인 |
| 보너스 Scheduling | 작업 A→B→C 순환 로그 | 앱 수준 패턴 확인 |

After의 종료 코드 143은 관측 시간 만료 후 실행 스크립트가 보낸 TERM 정리 결과다.
관측 구간 내 생존이며 장기 무장애 보장은 아니다.

## 검증 명령과 원본 기록

| 명령/자료 | 결과 |
| --- | --- |
| `./orbstack-machine.sh provision` (최종 코드) | [멱등 프로비저닝 통과](../evidence/validation/provision.log) |
| `./orbstack-machine.sh verify` (최종 코드) | [VM·권한·7개 시나리오 증거 검사 통과](../evidence/validation/vm-verification.log) |
| `bash tests/test_submission.sh` | [통과](../evidence/validation/local-tests.log), 관측 후 정리를 자체 종료로 오인하는 증거 거부 포함 |
| `python3 tests/check_evidence.py` | [정량·원본 인용 검사 통과](../evidence/validation/quantitative.log), CPU 한계 표시 |
| `python3 tests/check_evidence.py --strict-cpu` | [실패, 종료 코드 1](../evidence/validation/strict-cpu.log): OS CPU 50% 기준 미달 |
| 환경·포트·바이너리 해시 | [환경 스냅샷](../evidence/validation/environment.txt) |
| 실제 전체 실행 기록 | [demo 원본](../evidence/validation/demo.log) |
| 별도 증거 회수 | [collect 통과](../evidence/validation/collect.log) |

엄격 CPU 검증의 50%는 이 저장소에서 명시적으로 정한 기준이며 미션이 지정한 수치는
아니다. 낮은 실측 CPU를 앱 내부 55.65%로 대체해 성공 처리하지 않는다.

전체 실행 중 호스트 스크립트를 수정하여 마지막 단계에 셸 파싱 오류가 발생했다.
7개 시나리오 및 VM 내부 검사는 그 전에 완료됐으며, 이후 최종 코드로 `collect`,
멱등 `provision`, `verify`를 별도 실행해 각각 성공을 확인했다. 원본 실행 기록의 오류는
삭제하지 않았다. VM 최초 구성 중 공유 마운트 읽기와 Ubuntu 안내 서비스 시작 훅에서
대기한 이력이 있으며, 이번 작업의 해당 대기 프로세스만 정리하고 재시도했다.
호스트 공유 마운트 의존은 VM 내부 스테이징 전송으로 제거했다.
저장한 demo 로그의 터미널 CR 줄바꿈은 LF로 정규화했다.

## 남은 항목

CPU 보호 정책의 종료·회피는 확인했지만, 실제 프로세스 CPU 급상승과 요청 지연은
재현되지 않았다. 제공자에게 이 바이너리의 `Current Load` 정의 및 실제 부하 재현
조건을 확인해야 한다. 현재 결과를 전체 미션 100% 충족으로 판정하지 않는다.

리포트의 원본 인용을 최신 수집 파일과 대조했고 관측 사실·추론·제안을 구분했다.
재사용 양식은 [issue-template.md](issue-template.md)다. 제출 자료는 Markdown 리포트와
원본 증거 파일로 구성되며 PDF는 생성하지 않았다.
