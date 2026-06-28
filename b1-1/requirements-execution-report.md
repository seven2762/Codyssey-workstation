# Agent App 요구사항 수행 내역서

작성일: 2026-06-28
검증 환경: OrbStack Ubuntu 24.04 Linux machine, amd64

## 1. 수행 요약

초기에는 Docker 컨테이너 기반 구성을 검토했으나, 컨테이너 내부에서 UFW/iptables를 적용하려면 `NET_ADMIN`, `NET_RAW` capability가 필요했다. 이는 앱 컨테이너에 네트워크 관리 권한을 추가로 부여하는 방식이므로, 실제 서버 운영 환경의 보안 설정을 직접 구성한다는 미션 목적과 맞지 않는다고 판단했다.

따라서 Ubuntu 24.04 기반 OrbStack Linux machine에서 다음 항목을 OS 레벨로 구성했다.

- SSH 포트를 `20022`로 변경하고 root 원격 접속을 차단한다.
- UFW를 활성화하고 inbound 허용 포트를 `20022/tcp`, `15034/tcp`로 제한한다.
- 계정 `agent-admin`, `agent-dev`, `agent-test`를 생성한다.
- 그룹 `agent-common`, `agent-core`를 생성하고 계정별 그룹 멤버십을 부여한다.
- 앱 디렉토리, 업로드 디렉토리, API 키 디렉토리, 모니터링 스크립트 디렉토리, 로그 디렉토리를 생성한다.
- 디렉토리 권한과 ACL을 설정한다.
- 앱 실행에 필요한 환경 변수를 `/etc/agent-app/agent-app.env`에 설정한다.
- 키 파일 `$AGENT_HOME/api_keys/t_secret.key`를 생성하고 `agent_api_key_test` 1줄을 기록한다.
- 앱을 root가 아닌 일반 계정 `agent-admin`으로 실행한다.
- `systemd` 서비스로 앱을 관리한다.
- `monitor.sh`를 배치하고 `agent-admin` crontab에 매분 실행되도록 등록한다.
- `check-permissions.sh`로 `agent-admin`, `agent-dev`, `agent-test`의 권한 분리를 검증한다.

## 2. 실행 절차

OrbStack machine 생성:

```bash
orb create --arch amd64 ubuntu:noble b1-agent
orb -m b1-agent
```

bootstrap 스크립트 실행:

```bash
sudo apt-get update
sudo apt-get install -y curl
curl -fsSL https://raw.githubusercontent.com/seven2762/Codyssey-workstation/b1-1/bootstrap-orbstack.sh -o bootstrap-orbstack.sh
chmod +x bootstrap-orbstack.sh
./bootstrap-orbstack.sh
```

bootstrap 스크립트는 `https://github.com/seven2762/Codyssey-workstation.git` 저장소의 `b1-1` 브랜치를 `${HOME}/Codyssey-workstation`에 clone/update한 뒤 `b1-1/provision-orbstack.sh`를 실행한다.

주의: 프로비저닝 스크립트는 미션 전용 machine을 전제로 `ufw --force reset`을 실행한다. 기존 서비스가 함께 동작하는 공용 서버나 운영 VM에서는 사용하지 않는다.

검증:

```bash
sudo ./verify-orbstack.sh
```

## 3. 설정/명령어 기록

### SSH

`provision-orbstack.sh`에서 OpenSSH 서버를 설치하고 `/etc/ssh/sshd_config`를 다음 값으로 설정한다.

```text
Port 20022
PermitRootLogin no
```

서비스 적용:

```bash
systemctl enable ssh
systemctl restart ssh
```

### 방화벽

VM OS의 UFW를 초기화하고 inbound 기본 정책을 deny로 설정한 뒤 필요한 포트만 허용한다.

```bash
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow 20022/tcp
ufw allow 15034/tcp
ufw --force enable
```

### 계정/그룹

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

주요 경로:

```text
/home/agent-admin/agent-app
/home/agent-admin/agent-app/upload_files
/home/agent-admin/agent-app/api_keys
/home/agent-admin/agent-app/bin
/var/log/agent-app
```

권한 정책:

- `upload_files`: `agent-admin:agent-common`, `770`
- `api_keys`: `agent-admin:agent-core`, `770`
- `t_secret.key`: `agent-admin:agent-core`, `640`
- `/var/log/agent-app`: `agent-admin:agent-core`, `770`
- `monitor.sh`: `agent-dev:agent-core`, `750`
- `check-permissions.sh`: `agent-dev:agent-core`, `750`

ACL:

```bash
setfacl -m g:agent-common:rwx /home/agent-admin/agent-app/upload_files
setfacl -d -m g:agent-common:rwx /home/agent-admin/agent-app/upload_files
setfacl -m g:agent-core:rwx /home/agent-admin/agent-app/api_keys
setfacl -d -m g:agent-core:rwx /home/agent-admin/agent-app/api_keys
setfacl -m g:agent-core:rwx /var/log/agent-app
setfacl -d -m g:agent-core:rwx /var/log/agent-app
```

### 환경 변수

`/etc/agent-app/agent-app.env`:

```bash
AGENT_HOME=/home/agent-admin/agent-app
AGENT_PORT=15034
AGENT_UPLOAD_DIR=/home/agent-admin/agent-app/upload_files
AGENT_KEY_PATH=/home/agent-admin/agent-app/api_keys/t_secret.key
AGENT_LOG_DIR=/var/log/agent-app
```

### 앱 실행

앱은 `systemd` 서비스로 관리하며 `agent-admin` 계정으로 실행한다.

```ini
[Service]
User=agent-admin
Group=agent-admin
EnvironmentFile=/etc/agent-app/agent-app.env
WorkingDirectory=/home/agent-admin/agent-app
ExecStart=/home/agent-admin/agent-app/agent-app
Restart=on-failure
```

관리 명령:

```bash
systemctl status agent-app --no-pager
systemctl restart agent-app
journalctl -u agent-app -f
```

### cron

`agent-admin` 사용자 crontab에 `monitor.sh` 매분 실행을 등록한다.

```bash
* * * * * /bin/bash /home/agent-admin/agent-app/bin/monitor.sh >> /var/log/agent-app/cron.log 2>&1
```

## 4. 검증 명령

```bash
grep -E "^(Port|PermitRootLogin)" /etc/ssh/sshd_config
ss -tulnp | grep -E ":20022\b|:15034\b"
ufw status verbose
id agent-admin
id agent-dev
id agent-test
getent group agent-common
getent group agent-core
ls -ld /home/agent-admin/agent-app /home/agent-admin/agent-app/upload_files /home/agent-admin/agent-app/api_keys /home/agent-admin/agent-app/bin /var/log/agent-app
getfacl -p /home/agent-admin/agent-app/upload_files /home/agent-admin/agent-app/api_keys /var/log/agent-app
systemctl status agent-app --no-pager
crontab -u agent-admin -l
tail -n 10 /var/log/agent-app/monitor.log
sudo /home/agent-admin/agent-app/bin/check-permissions.sh
```

## 5. Docker capability와 VM의 차이

Docker 컨테이너는 호스트 커널을 공유하면서 프로세스, 파일시스템, 네트워크 namespace를 격리한다. 기본 상태의 컨테이너는 호스트 네트워크 스택을 관리할 권한이 없기 때문에 UFW/iptables 조작이 제한된다.

`NET_ADMIN`을 추가하면 컨테이너 안의 프로세스가 네트워크 인터페이스, 라우팅, 방화벽 규칙 같은 네트워크 관리 기능을 사용할 수 있다. `NET_RAW`를 추가하면 raw socket 사용이 가능해진다. 이는 앱 실행 단위인 컨테이너에 운영체제 네트워크 관리 권한을 일부 넘기는 것이므로 컨테이너 격리 원칙을 약화시킨다.

반면 VM은 운영체제 자체를 실행하는 서버 단위다. VM 안의 UFW, SSH, cron, 사용자/그룹, ACL은 그 VM의 OS를 관리하는 정상적인 운영 작업이다. 따라서 이 미션처럼 서버 운영 환경 구축을 학습할 때는 VM에서 직접 구성하는 방식이 더 목적에 맞다.
