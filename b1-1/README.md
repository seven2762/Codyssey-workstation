# monitor.sh 비정상 종료 시연

`monitor.sh`의 Health Check 실패 시 오류 메시지를 출력하고 종료 코드 `1`을
반환하는지 확인하는 방법입니다.

## 권장: 사용하지 않는 포트로 포트 검사 실패 유도

실행 중인 `agent-app` 서비스에는 영향을 주지 않습니다. `65000` 포트가
LISTEN 상태가 아닌 환경에서 실행합니다.

```bash
sudo -u agent-admin bash -c 'AGENT_PORT=65000 /bin/bash /home/agent-admin/agent-app/bin/monitor.sh'
echo "exit=$?"
```

예상 결과:

```text
[YYYY-MM-DD HH:MM:SS] [ERROR] TCP 65000 포트가 LISTEN 상태가 아닙니다. 모니터링을 종료합니다.
exit=1
```

## 대안: 프로세스 미실행 상태 확인

`agent-app` 프로세스가 실행 중이지 않은 상태에서 아래 명령을 실행합니다.

```bash
sudo -u agent-admin /bin/bash /home/agent-admin/agent-app/bin/monitor.sh
echo "exit=$?"
```

예상 결과:

```text
[YYYY-MM-DD HH:MM:SS] [ERROR] 프로세스 'agent-app' 가 실행 중이지 않습니다. 모니터링을 종료합니다.
exit=1
```

서비스를 중지해 시연한 경우에는 즉시 다시 시작합니다.

```bash
sudo systemctl start agent-app
```
