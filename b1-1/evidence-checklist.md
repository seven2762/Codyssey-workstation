# Agent App 필수 증거 자료 체크리스트

작성일: 2026-06-28
검증 환경: OrbStack Ubuntu 24.04 Linux machine, amd64

## 체크리스트

| 항목 | 상태 | 확인 내역 |
| --- | --- | --- |
| SSH 포트 `20022` 변경 | 준비 | `/etc/ssh/sshd_config`에서 `Port 20022` 확인 |
| Root 원격 접속 차단 | 준비 | `/etc/ssh/sshd_config`에서 `PermitRootLogin no` 확인 |
| 방화벽 활성화 | 준비 | `ufw status verbose`에서 `Status: active` 확인 |
| 방화벽 허용 포트 제한 | 준비 | UFW inbound 허용 규칙 `20022/tcp`, `15034/tcp` 확인 |
| 계정 생성 | 준비 | `agent-admin`, `agent-dev`, `agent-test` 확인 |
| 그룹 생성 | 준비 | `agent-common`, `agent-core` 확인 |
| 그룹 멤버십 | 준비 | `agent-common`: admin/dev/test, `agent-core`: admin/dev 확인 |
| 디렉토리 구조/권한 | 준비 | 앱/업로드/API 키/bin/log 디렉토리 권한 확인 |
| ACL 설정 | 준비 | `getfacl`에서 `agent-common`, `agent-core` ACL 확인 |
| 환경 변수 구성 | 준비 | `/etc/agent-app/agent-app.env` 확인 |
| 키 파일 생성 | 준비 | `$AGENT_HOME/api_keys/t_secret.key`, 내용 `agent_api_key_test` |
| 일반 계정 실행 | 준비 | `systemctl status agent-app`에서 `User=agent-admin` 서비스 확인 |
| 앱 Boot Sequence 5단계 | 준비 | `journalctl -u agent-app`에서 `[1/5]`부터 `[5/5]`까지 `[OK]` 확인 |
| `Agent READY` | 준비 | `journalctl -u agent-app`에서 `Agent READY` 확인 |
| 앱 포트 LISTEN | 준비 | `0.0.0.0:15034` LISTEN 확인 |
| monitor.sh 파일 정책 | 준비 | 경로 `$AGENT_HOME/bin/monitor.sh`, 소유자 `agent-dev`, 그룹 `agent-core`, 권한 `750` 확인 |
| monitor.sh Health Check | 준비 | 프로세스/포트 비정상 시 `[ERROR]` 후 `exit 1` 로직 확인 |
| monitor.sh 방화벽 경고 | 준비 | UFW/firewalld 비활성 시 `[WARNING]`, 종료하지 않음 |
| monitor.sh 자원/임계값 | 준비 | CPU/MEM/DISK_USED 수집 및 CPU>20, MEM>10, DISK_USED>80 경고 로직 확인 |
| monitor.log 용량 관리 | 준비 | 스크립트 로직으로 최대 10MB/10개 파일 유지 |
| `monitor.sh` 실행 결과 | 준비 | CPU/MEM 경고 및 PID/자원 로그 기록 확인 |
| `monitor.log` 누적 기록 | 준비 | 최근 라인에서 `PID`, `CPU`, `MEM`, `DISK_USED` 확인 |
| crontab 매분 등록 | 준비 | `* * * * * /bin/bash .../monitor.sh` 확인 |
| cron 자동 실행 확인 | 준비 | 70초 후 `monitor.log`, `cron.log` 라인 증가 확인 |

## 통합 검증

OrbStack machine 안에서 다음 명령을 실행한다.

```bash
cd <repository>/b1-1
sudo ./verify-orbstack.sh
```

## 개별 증거 수집 명령

### 1. SSH 포트 변경 및 Root 원격 접속 차단

```bash
sudo grep -E "^(Port|PermitRootLogin)" /etc/ssh/sshd_config
ss -tulnp | grep -E ":20022\b|:15034\b"
```

### 2. 방화벽 활성화 및 허용 포트

```bash
sudo ufw status verbose
```

기대 결과:

```text
Status: active
Default: deny (incoming), allow (outgoing), deny (routed)
20022/tcp                  ALLOW IN    Anywhere
15034/tcp                  ALLOW IN    Anywhere
```

### 3. 계정/그룹 생성 확인

```bash
id agent-admin
id agent-dev
id agent-test
getent group agent-common
getent group agent-core
```

### 4. 디렉토리 구조 및 권한 확인

```bash
sudo ls -ld \
  /home/agent-admin/agent-app \
  /home/agent-admin/agent-app/upload_files \
  /home/agent-admin/agent-app/api_keys \
  /home/agent-admin/agent-app/bin \
  /var/log/agent-app

sudo ls -l \
  /home/agent-admin/agent-app/api_keys/t_secret.key \
  /home/agent-admin/agent-app/bin/monitor.sh
```

### 5. ACL 확인

```bash
sudo getfacl -p \
  /home/agent-admin/agent-app/upload_files \
  /home/agent-admin/agent-app/api_keys \
  /var/log/agent-app
```

### 6. 앱 Boot Sequence 및 Agent READY

```bash
sudo journalctl -u agent-app --no-pager | grep -E "\[[1-5]/5\]|Agent READY"
```

### 7. 앱 서비스 상태

```bash
systemctl status agent-app --no-pager
systemctl is-active agent-app
```

### 8. 환경 변수

```bash
sudo cat /etc/agent-app/agent-app.env
```

### 9. monitor.sh 직접 실행

```bash
sudo -u agent-admin /bin/bash /home/agent-admin/agent-app/bin/monitor.sh
sudo tail -n 10 /var/log/agent-app/monitor.log
```

### 10. cron 매분 실행 및 로그 증가 증거

```bash
sudo crontab -u agent-admin -l
sudo wc -l /var/log/agent-app/monitor.log /var/log/agent-app/cron.log
sleep 70
sudo wc -l /var/log/agent-app/monitor.log /var/log/agent-app/cron.log
```
