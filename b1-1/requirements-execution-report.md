# Agent App 요구사항 수행 내역서

작성일: 2026-06-16
문서 보강일: 2026-06-17
검증 환경: Docker/Colima, Ubuntu 24.04 컨테이너, linux/amd64
검증 이미지: `b1-agent-app:proof`
최종 검증 컨테이너: `b1-agent-proof-20260616-1920`
컨테이너 기준 시각: UTC

## 1. 수행 요약

Agent App 실행 환경을 Docker 이미지로 구성하고 다음 항목을 설정했다.

- SSH 포트를 `20022`로 변경하고 root 원격 접속을 차단했다.
- UFW를 활성화하고 inbound 허용 포트를 `20022/tcp`, `15034/tcp`로 제한했다.
- 계정 `agent-admin`, `agent-dev`, `agent-test`를 생성했다.
- 그룹 `agent-common`, `agent-core`를 생성하고 계정별 그룹 멤버십을 부여했다.
- 앱 디렉토리, 업로드 디렉토리, API 키 디렉토리, 모니터링 스크립트 디렉토리, 로그 디렉토리를 생성했다.
- 디렉토리 권한과 ACL을 설정했다.
- 앱 실행에 필요한 환경 변수를 설정했다.
- 키 파일 `$AGENT_HOME/api_keys/t_secret.key`를 생성하고 `agent_api_key_test` 1줄을 기록했다.
- 앱을 root가 아닌 일반 계정 `agent-admin`으로 실행했다.
- `monitor.sh`를 배치하고 `agent-admin` crontab에 매분 실행되도록 등록했다.
- 앱 Boot Sequence 5단계 `[OK]`와 `Agent READY`를 확인했다.
- 앱이 `0.0.0.0:15034`로 LISTEN 상태임을 확인했다.

## 2. 설정/명령어 기록

### SSH

Dockerfile에서 OpenSSH 서버를 설치하고 `/etc/ssh/sshd_config`를 다음과 같이 설정했다.

```bash
mkdir -p /var/run/sshd
sed -i 's/#Port 22/Port 20022/' /etc/ssh/sshd_config
sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config
echo "PermitRootLogin no" >> /etc/ssh/sshd_config
```

컨테이너 시작 시 SSH 데몬을 실행했다.

```bash
service ssh start
```

### 방화벽

컨테이너 시작 시 UFW를 초기화하고 inbound 기본 정책을 deny로 설정한 뒤 필요한 포트만 허용했다.

```bash
update-alternatives --set iptables /usr/sbin/iptables-legacy
update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow 20022/tcp
ufw allow 15034/tcp
ufw --force enable
```

### 계정/그룹

Dockerfile에서 다음 계정과 그룹을 생성했다.

```bash
groupadd agent-common
groupadd agent-core
useradd -m -s /bin/bash agent-admin
useradd -m -s /bin/bash agent-dev
useradd -m -s /bin/bash agent-test
usermod -aG agent-common agent-admin
usermod -aG agent-common agent-dev
usermod -aG agent-common agent-test
usermod -aG agent-core agent-admin
usermod -aG agent-core agent-dev
```

그룹 정책:

- `agent-common`: `agent-admin`, `agent-dev`, `agent-test`
- `agent-core`: `agent-admin`, `agent-dev`

### 디렉토리/권한/ACL

생성 디렉토리:

```bash
mkdir -p /home/agent-admin/agent-app/upload_files \
         /home/agent-admin/agent-app/api_keys \
         /home/agent-admin/agent-app/bin \
         /var/log/agent-app
```

권한 설정:

```bash
chown -R agent-admin:agent-admin /home/agent-admin/agent-app
chown agent-admin:agent-common /home/agent-admin/agent-app/upload_files
chmod 770 /home/agent-admin/agent-app/upload_files
chown -R agent-admin:agent-core /home/agent-admin/agent-app/api_keys
chmod 770 /home/agent-admin/agent-app/api_keys
chmod o-rwx /home/agent-admin/agent-app/api_keys
chmod 640 /home/agent-admin/agent-app/api_keys/t_secret.key
chown agent-admin:agent-core /var/log/agent-app
chmod 770 /var/log/agent-app
chmod o-rwx /var/log/agent-app
chown agent-dev:agent-core /home/agent-admin/agent-app/bin/monitor.sh
chmod 750 /home/agent-admin/agent-app/bin/monitor.sh
```

ACL 설정:

```bash
setfacl -m g:agent-common:rwx /home/agent-admin/agent-app/upload_files
setfacl -d -m g:agent-common:rwx /home/agent-admin/agent-app/upload_files
setfacl -m g:agent-core:rwx /home/agent-admin/agent-app/api_keys
setfacl -d -m g:agent-core:rwx /home/agent-admin/agent-app/api_keys
setfacl -m g:agent-core:rwx /var/log/agent-app
setfacl -d -m g:agent-core:rwx /var/log/agent-app
```

### 환경 변수

Dockerfile 및 entrypoint에서 다음 환경 변수를 설정했다.

```bash
AGENT_HOME=/home/agent-admin/agent-app
AGENT_PORT=15034
AGENT_UPLOAD_DIR=/home/agent-admin/agent-app/upload_files
AGENT_LOG_DIR=/var/log/agent-app
AGENT_KEY_PATH=/home/agent-admin/agent-app/api_keys/t_secret.key
```

### 키 파일

앱에서 요구하는 API 키 파일을 다음 경로와 내용으로 생성했다.

```bash
echo 'agent_api_key_test' > /home/agent-admin/agent-app/api_keys/t_secret.key
```

- 경로: `$AGENT_HOME/api_keys/t_secret.key`
- 내용: `agent_api_key_test` 1줄
- 권한: `640`
- 소유/그룹: `agent-admin:agent-core`

### 앱 실행

앱은 root가 아닌 `agent-admin` 계정으로 실행했다.

```bash
su -s /bin/bash agent-admin -c '
  export AGENT_HOME=/home/agent-admin/agent-app
  export AGENT_PORT=15034
  export AGENT_UPLOAD_DIR=/home/agent-admin/agent-app/upload_files
  export AGENT_KEY_PATH=/home/agent-admin/agent-app/api_keys/t_secret.key
  export AGENT_LOG_DIR=/var/log/agent-app
  cd ${AGENT_HOME}
  ./agent-app
'
```

성공 기준:

- Boot Sequence 5단계가 모두 `[OK]`
- 마지막에 `Agent READY` 출력
- 앱이 `0.0.0.0:15034`로 LISTEN
- 수동 종료 시 `Ctrl+C` 사용

### cron

`agent-admin` 사용자 crontab에 `monitor.sh` 매분 실행을 등록했다.

```bash
echo '* * * * * /bin/bash /home/agent-admin/agent-app/bin/monitor.sh >> /var/log/agent-app/cron.log 2>&1' | crontab -u agent-admin -
```

### monitor.sh

`monitor.sh`는 `$AGENT_HOME/bin/monitor.sh`에 배치했다.

- 소유자: `agent-dev`
- 그룹: `agent-core`
- 권한: `750` (`rwxr-x---`)
- cron 실행 계정: `agent-admin`
- `agent-admin`은 `agent-core` 그룹에 포함되어 실행 가능

Health Check:

- 프로세스: 제공 앱 바이너리명 `agent-app` 실행 상태 확인
- 포트: TCP `15034` LISTEN 상태 확인
- 프로세스 또는 포트 확인 실패 시 `[ERROR]`를 기록하고 `exit 1`

상태 점검:

- UFW/firewalld 활성화 상태 점검
- 비활성 상태면 `[WARNING]` 출력
- 방화벽 경고는 스크립트 종료 조건이 아님

자원 수집:

- CPU 사용률 `%`
- 메모리 사용률 `%`
- Root partition 디스크 사용률 `%`

임계값 경고:

- `CPU > 20%`: `[WARNING]`
- `MEM > 10%`: `[WARNING]`
- `DISK_USED > 80%`: `[WARNING]`

로그:

- 로그 파일: `/var/log/agent-app/monitor.log`
- 로그 포맷: `[YYYY-MM-DD HH:MM:SS] PID:... CPU:..% MEM:..% DISK_USED:..%`
- 로그 용량 관리: 스크립트 자체 로직으로 `monitor.log` 최대 10MB, 로테이션 파일 최대 10개 유지

## 3. 빌드/실행/검증 명령 기록

이미지 빌드:

```bash
docker build --platform linux/amd64 -t b1-agent-app:proof .
```

검증 컨테이너 실행:

```bash
docker run --platform linux/amd64 --cap-add NET_ADMIN --cap-add NET_RAW -d --name b1-agent-proof-20260616-1920 b1-agent-app:proof
```

주요 검증 명령:

```bash
docker logs --since 2026-06-16T10:43:52Z --until 2026-06-16T10:44:45Z b1-agent-proof-20260616-1920
docker exec b1-agent-proof-20260616-1920 bash -lc 'grep -E "^(Port|PermitRootLogin)" /etc/ssh/sshd_config; ss -tulnp | grep -E ":20022\b|:15034\b"; ufw status verbose'
docker exec b1-agent-proof-20260616-1920 bash -lc 'id agent-admin; id agent-dev; id agent-test; getent group agent-common; getent group agent-core'
docker exec b1-agent-proof-20260616-1920 bash -lc 'ls -ld /home/agent-admin/agent-app /home/agent-admin/agent-app/upload_files /home/agent-admin/agent-app/api_keys /home/agent-admin/agent-app/bin /var/log/agent-app; getfacl -p /home/agent-admin/agent-app/upload_files /home/agent-admin/agent-app/api_keys /var/log/agent-app'
docker exec b1-agent-proof-20260616-1920 bash -lc '/bin/bash /home/agent-admin/agent-app/bin/monitor.sh; tail -n 10 /var/log/agent-app/monitor.log'
docker exec b1-agent-proof-20260616-1920 bash -lc 'crontab -u agent-admin -l; wc -l /var/log/agent-app/monitor.log /var/log/agent-app/cron.log'
```

## 4. 변경 보완 사항

검증 중 `monitor.sh`가 `agent-admin` 권한으로 실행될 때 `ufw status` 권한 부족으로 실제 active 상태를 비활성으로 오판하는 문제가 확인되어 보완했다.

- root 실행 시: `ufw status` 결과의 `Status: active` 확인
- 비root 실행 시: `/etc/ufw/ufw.conf`의 `ENABLED=yes`를 fallback으로 확인

또한 API 키 파일 권한 증거가 디렉토리 그룹 정책과 일치하도록 `api_keys` 하위 파일까지 `agent-core` 그룹 소유가 되도록 보완했다.
