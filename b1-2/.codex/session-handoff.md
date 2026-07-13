# Session Handoff

## 현재 목표

`b1-1` 브랜치와 같은 사용감으로 `b1-2` 과제를 OrbStack VM에서 한 명령으로
프로비저닝하고, 장애 Before/After를 재현하고, 증거를 자동 검증·회수할 수 있게 한다.

## 완료한 작업

- `orbstack-machine.sh`에 create/start/provision/run-all/verify/collect/demo/reset-demo 구현
- `provision-orbstack.sh`로 amd64 검증, `agent(uid=1000)` 생성, 런타임 멱등 설치
- `setup-agent-env.sh`로 필수 디렉터리, 테스트 키, source 가능한 `.env` 구성
- `run-all-scenarios.sh`로 OOM/CPU/Deadlock Before·After와 Scheduling 7개 실행
- `run-scenario.sh`에 입력 검증, 대상 프로세스 트리 정리, `run.log` 기록 추가
- `verify-results.sh`, `verify-orbstack.sh`로 결과와 VM 환경 통합 검증
- README에 한 줄 데모와 단계별 명령 문서화
- 실제 `b1-2-agent` amd64 OrbStack VM에서 demo 전체 실행 및 증거 회수
- 보안 검토 후 machine/path 입력 검증 및 문자열 기반 원격 명령 조립 제거

## 변경 파일

- 자동화: `orbstack-machine.sh`, `provision-orbstack.sh`, `setup-agent-env.sh`
- 실행/검증: `run-scenario.sh`, `run-all-scenarios.sh`, `monitor.sh`,
  `verify-results.sh`, `verify-orbstack.sh`
- 테스트/문서: `tests/test_submission.sh`, `README.md`
- 실제 증거: `evidence/` 아래 7개 자동화 시나리오의 app/monitor/thread/run 로그

## 검증 결과

- `bash tests/test_submission.sh`: PASS
- `EVIDENCE_ROOT=$PWD/evidence bash verify-results.sh`: PASS
- 전체 대상 셸 스크립트 `bash -n`: PASS
- `git diff --check`: PASS
- 실제 OrbStack demo: 7개 시나리오 판정 PASS
- 실제 `./orbstack-machine.sh verify`: VM/계정/권한/증거 전체 PASS
- OOM Before 137, CPU Before 143, After 시나리오 timed_out=true 확인

## 미해결 이슈

- 없음. 최종 GREEN 커밋과 필요 시 원격 push만 남았다.

## 다음 액션

1. `test.sh`를 제외한 `b1-2` 변경만 명시적으로 stage한다.
2. staged diff와 파일 모드를 확인한다.
3. GREEN 커밋을 생성한다.
4. 사용자가 원하면 `origin/b1-2`로 push한다.

## 주의할 점

- `b1-2/test.sh`는 기존 미추적 개인 파일이며 문법 오류가 있다. 수정·추가·삭제하지 않는다.
- 저장소 루트의 다른 과제 폴더는 현재 브랜치에서 추적하지 않으며 건드리지 않는다.
- `reset-demo`는 `MACHINE_NAME`으로 지정한 VM을 삭제하므로 명시적으로 요청된 경우만 쓴다.
- `collect`는 실제 재현 로그를 갱신하므로 타임스탬프와 PID가 실행마다 바뀐다.
