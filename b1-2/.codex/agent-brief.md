# Agent Brief

1. 먼저 `.codex/session-handoff.md`를 읽고 현재 작업 맥락을 파악한다.
2. `git status --short`로 실제 작업트리 상태를 확인한다.
3. 할당받은 범위 밖 파일은 수정하지 않는다.
4. 다른 세션이나 에이전트가 만든 변경을 되돌리지 않는다.
5. 작업 완료 시 `.codex/agent-results/<agent-name>.md`에 변경 파일, 검증 결과,
   남은 리스크를 적는다.
6. `.codex/session-handoff.md`는 메인 세션만 수정한다.
7. 미추적 `test.sh`는 사용자 개인 파일이므로 건드리지 않는다.
