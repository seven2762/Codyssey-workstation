# b1-1 Agent App

Agent App 실행 환경을 Docker 컨테이너로 구성하고, SSH/UFW/계정/권한/ACL/cron/monitoring 요구사항을 검증한 프로젝트입니다.

검증 기준:

- 검증일: 2026-06-16
- 검증 이미지: `b1-agent-app:proof`
- 검증 컨테이너: `b1-agent-proof-20260616-1920`
- 컨테이너 OS: Ubuntu 24.04
- 컨테이너 기준 시각: UTC

## 프로젝트 파일

| 파일 | 설명 |
| --- | --- |
| `b1-1/Dockerfile` | Ubuntu 24.04 기반 환경, SSH/UFW/계정/권한/ACL/cron 구성 |
| `b1-1/entrypoint.sh` | SSH, cron, UFW 설정 후 `agent-admin` 계정으로 앱 실행 |
| `b1-1/monitor.sh` | 프로세스/포트/방화벽/CPU/MEM/DISK 점검 및 로그 기록 |
| `b1-1/agent-app` | 제공된 x86_64 Linux 실행 바이너리 |
| `b1-1/requirements-execution-report.md` | 요구사항 수행 내역서 |
| `b1-1/evidence-checklist.md` | 필수 증거 자료 체크리스트 |

## 빌드 및 실행

`agent-app`은 x86_64 ELF 바이너리이므로 Apple Silicon 환경에서도 `linux/amd64` 플랫폼을 명시했습니다.

```bash
cd b1-1
docker build --platform linux/amd64 -t b1-agent-app:proof .
```

검증용 실행 명령:

```bash
docker run --platform linux/amd64 \
  --cap-add NET_ADMIN --cap-add NET_RAW \
  -d \
  --name b1-agent-proof \
  -p 20022:20022 \
  -p 15034:15034 \
  b1-agent-app:proof
```

`NET_ADMIN`, `NET_RAW` capability는 컨테이너 내부에서 UFW/iptables 방화벽 설정을 적용하기 위해 부여했습니다.

## 1. SSH 포트 변경 및 root 접속 차단

설정 내용:

```dockerfile
RUN mkdir -p /var/run/sshd && \
    sed -i 's/#Port 22/Port 20022/' /etc/ssh/sshd_config && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config && \
    echo "PermitRootLogin no" >> /etc/ssh/sshd_config
```

검증 명령:

```bash
docker exec b1-agent-proof-20260616-1920 bash -lc 'grep -E "^(Port|PermitRootLogin)" /etc/ssh/sshd_config'
docker exec b1-agent-proof-20260616-1920 bash -lc 'ss -tulnp | grep -E ":20022\b|:15034\b"'
```

실제 검증 결과:

```text
Port 20022
PermitRootLogin no
PermitRootLogin no

tcp   LISTEN 0      1            0.0.0.0:15034      0.0.0.0:*
tcp   LISTEN 0      128          0.0.0.0:20022      0.0.0.0:*    users:(("sshd",pid=15,fd=3))
tcp   LISTEN 0      128             [::]:20022         [::]:*    users:(("sshd",pid=15,fd=4))
```

보안 설명(위협 모델 관점):

- 기본 SSH 포트 22는 자동 스캔과 무차별 대입 공격의 주요 대상입니다. 20022로 변경하면 보안의 주 수단은 아니지만 무작위 스캔 노출을 줄이는 효과가 있습니다.
- `PermitRootLogin no`는 root 계정의 원격 직접 로그인 경로를 차단합니다. 공격자가 root 비밀번호나 키를 노려 바로 최고 권한을 얻는 위험을 줄이고, 일반 계정 로그인 후 필요한 경우에만 권한 상승하도록 강제합니다.

## 2. UFW 방화벽 활성화 및 허용 포트 제한

설정 내용:

```bash
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow 20022/tcp
ufw allow 15034/tcp
ufw --force enable
```

검증 명령:

```bash
docker exec b1-agent-proof-20260616-1920 bash -lc 'ufw status verbose'
```

실제 검증 결과:

```text
Status: active
Logging: on (low)
Default: deny (incoming), allow (outgoing), deny (routed)

To                         Action      From
--                         ------      ----
20022/tcp                  ALLOW IN    Anywhere
15034/tcp                  ALLOW IN    Anywhere
20022/tcp (v6)             ALLOW IN    Anywhere (v6)
15034/tcp (v6)             ALLOW IN    Anywhere (v6)
```

설명:

- inbound 기본 정책은 `deny`입니다.
- 명시적으로 허용한 inbound 포트는 SSH용 `20022/tcp`, 앱용 `15034/tcp`뿐입니다.
- outgoing은 앱/패키지 동작을 위해 `allow`로 유지했습니다.

## 3. 계정/그룹 구성

생성 계정:

- `agent-admin`: 운영/관리, cron 실행자
- `agent-dev`: 개발/운영, `monitor.sh` 작성자
- `agent-test`: QA/테스트

생성 그룹:

- `agent-common`: `agent-admin`, `agent-dev`, `agent-test`
- `agent-core`: `agent-admin`, `agent-dev`

설정 내용:

```dockerfile
RUN groupadd agent-common && groupadd agent-core

RUN useradd -m -s /bin/bash agent-admin && \
    useradd -m -s /bin/bash agent-dev   && \
    useradd -m -s /bin/bash agent-test

RUN usermod -aG agent-common agent-admin && \
    usermod -aG agent-common agent-dev   && \
    usermod -aG agent-common agent-test

RUN usermod -aG agent-core agent-admin && \
    usermod -aG agent-core agent-dev
```

검증 명령:

```bash
docker exec b1-agent-proof-20260616-1920 bash -lc 'id agent-admin; id agent-dev; id agent-test; getent group agent-common; getent group agent-core'
```

실제 검증 결과:

```text
uid=1001(agent-admin) gid=1003(agent-admin) groups=1003(agent-admin),1001(agent-common),1002(agent-core)
uid=1002(agent-dev) gid=1004(agent-dev) groups=1004(agent-dev),1001(agent-common),1002(agent-core)
uid=1003(agent-test) gid=1005(agent-test) groups=1005(agent-test),1001(agent-common)
agent-common:x:1001:agent-admin,agent-dev,agent-test
agent-core:x:1002:agent-admin,agent-dev
```

설명:

- 공통 업로드 작업은 `agent-common`으로 묶어 admin/dev/test 모두 접근 가능하게 했습니다.
- API 키와 로그는 운영 핵심 리소스이므로 `agent-core`로 제한해 admin/dev만 접근하게 했습니다.

## 4. 디렉토리 권한 및 ACL

디렉토리 구조:

```text
/home/agent-admin/agent-app
/home/agent-admin/agent-app/upload_files
/home/agent-admin/agent-app/api_keys
/home/agent-admin/agent-app/bin
/var/log/agent-app
```

핵심 정책:

- `upload_files`: group=`agent-common`, R/W 가능
- `api_keys`: group=`agent-core` only, R/W 가능
- `/var/log/agent-app`: group=`agent-core` only, R/W 가능
- `monitor.sh`: owner=`agent-dev`, group=`agent-core`, mode=`750`

설정 내용:

```dockerfile
RUN chown agent-admin:agent-common /home/agent-admin/agent-app/upload_files && \
    chmod 770 /home/agent-admin/agent-app/upload_files

RUN chown -R agent-admin:agent-core /home/agent-admin/agent-app/api_keys && \
    chmod 770 /home/agent-admin/agent-app/api_keys && \
    chmod o-rwx /home/agent-admin/agent-app/api_keys && \
    chmod 640 /home/agent-admin/agent-app/api_keys/t_secret.key

RUN chown agent-admin:agent-core /var/log/agent-app && \
    chmod 770 /var/log/agent-app && \
    chmod o-rwx /var/log/agent-app

RUN chown agent-dev:agent-core /home/agent-admin/agent-app/bin/monitor.sh && \
    chmod 750 /home/agent-admin/agent-app/bin/monitor.sh
```

ACL 설정:

```dockerfile
RUN setfacl -m g:agent-common:rwx /home/agent-admin/agent-app/upload_files && \
    setfacl -d -m g:agent-common:rwx /home/agent-admin/agent-app/upload_files && \
    setfacl -m g:agent-core:rwx /home/agent-admin/agent-app/api_keys && \
    setfacl -d -m g:agent-core:rwx /home/agent-admin/agent-app/api_keys && \
    setfacl -m g:agent-core:rwx /var/log/agent-app && \
    setfacl -d -m g:agent-core:rwx /var/log/agent-app
```

실제 권한 검증 결과:

```text
drwxr-xr-x  1 agent-admin agent-admin  4096 Jun 16 10:11 /home/agent-admin/agent-app
drwxrwx---+ 1 agent-admin agent-core   4096 Jun 16 10:11 /home/agent-admin/agent-app/api_keys
drwxr-xr-x  1 agent-admin agent-admin  4096 Jun 16 10:19 /home/agent-admin/agent-app/bin
drwxrwx---+ 1 agent-admin agent-common 4096 Jun 16 10:11 /home/agent-admin/agent-app/upload_files
drwxrwx---+ 1 agent-admin agent-core   4096 Jun 16 10:44 /var/log/agent-app
-rw-r----- 1 agent-admin agent-core   19 Jun 16 10:11 /home/agent-admin/agent-app/api_keys/t_secret.key
-rwxr-x--- 1 agent-dev   agent-core 9093 Jun 16 10:19 /home/agent-admin/agent-app/bin/monitor.sh
```

실제 ACL 검증 결과:

```text
# file: /home/agent-admin/agent-app/upload_files
# owner: agent-admin
# group: agent-common
user::rwx
group::rwx
group:agent-common:rwx
mask::rwx
other::---
default:user::rwx
default:group::rwx
default:group:agent-common:rwx
default:mask::rwx
default:other::---

# file: /home/agent-admin/agent-app/api_keys
# owner: agent-admin
# group: agent-core
user::rwx
group::rwx
group:agent-core:rwx
mask::rwx
other::---
default:user::rwx
default:group::rwx
default:group:agent-core:rwx
default:mask::rwx
default:other::---

# file: /var/log/agent-app
# owner: agent-admin
# group: agent-core
user::rwx
group::rwx
group:agent-core:rwx
mask::rwx
other::---
default:user::rwx
default:group::rwx
default:group:agent-core:rwx
default:mask::rwx
default:other::---
```

최소 권한 원칙 설명:

- `api_keys`는 앱 인증 키가 저장되는 민감 디렉토리입니다. QA 계정인 `agent-test`가 읽을 필요가 없으므로 `agent-core`에만 권한을 부여했습니다.
- `/var/log/agent-app`는 운영 상태와 경고가 남는 디렉토리입니다. 운영자와 개발자만 확인/기록하면 충분하므로 `agent-core`로 제한했습니다.
- `upload_files`는 QA까지 테스트가 필요한 공유 영역이라 `agent-common`으로 열었습니다.
- ACL은 기본 `chown/chmod`보다 여러 사용자/그룹별 권한과 default 상속 권한을 명시할 수 있어 협업 권한을 증명하기 좋습니다.

## 5. 앱 실행 환경 및 키 파일

환경 변수:

```text
AGENT_HOME=/home/agent-admin/agent-app
AGENT_PORT=15034
AGENT_UPLOAD_DIR=/home/agent-admin/agent-app/upload_files
AGENT_KEY_PATH=/home/agent-admin/agent-app/api_keys/t_secret.key
AGENT_LOG_DIR=/var/log/agent-app
```

키 파일:

```dockerfile
RUN echo 'agent_api_key_test' > /home/agent-admin/agent-app/api_keys/t_secret.key
```

키 파일 검증 결과:

```text
경로: /home/agent-admin/agent-app/api_keys/t_secret.key
내용: agent_api_key_test
권한: -rw-r----- 1 agent-admin agent-core
```

앱 실행 방식:

```bash
exec su -s /bin/bash agent-admin -c "
    export AGENT_HOME=${AGENT_HOME}
    export AGENT_PORT=${AGENT_PORT}
    export AGENT_UPLOAD_DIR=${AGENT_UPLOAD_DIR}
    export AGENT_KEY_PATH=${AGENT_KEY_PATH}
    export AGENT_LOG_DIR=${AGENT_LOG_DIR}
    cd \${AGENT_HOME}
    ./agent-app
"
```

설명:

- 앱은 root로 실행하지 않고 `agent-admin` 일반 계정으로 실행합니다.
- root 실행을 피하면 앱 취약점이 발생해도 컨테이너 내부 최고 권한 탈취 위험을 줄일 수 있습니다.

## 6. Boot Sequence 및 앱 LISTEN 검증

검증 명령:

```bash
docker logs --since 2026-06-16T10:43:52Z --until 2026-06-16T10:44:45Z b1-agent-proof-20260616-1920
```

실제 검증 결과:

```text
>>> Starting Agent Boot Sequence...
[1/5] Checking User Account               [OK]
 ... Running as service user 'agent-admin' (uid=1001)
[2/5] Verifying Environment Variables     [OK]
 ... All required Envs correct
[3/5] Checking Required Files             [OK]
 ... Verified 'secret.key' with correct key string.
[4/5] Checking Port Availability          [OK]
 ... Port 15034 is available.
[5/5] Verifying Log Permission            [OK]
 ... Log directory is writable: /var/log/agent-app
------------------------------------------------------------
All Boot Checks Passed!
Agent READY
2026-06-16 10:44:00,249 [INFO] Agent listening at port 15034
```

포트 검증 결과:

```text
tcp   LISTEN 0      1            0.0.0.0:15034      0.0.0.0:*
```

## 7. monitor.sh 구현 및 Health Check

파일 정책:

```text
경로: /home/agent-admin/agent-app/bin/monitor.sh
소유자: agent-dev
그룹: agent-core
권한: 750 (rwxr-x---)
cron 실행 계정: agent-admin
```

`agent-admin`은 `agent-core` 그룹에 포함되어 있으므로 cron에서 `monitor.sh`를 실행할 수 있습니다.

프로세스 Health Check 코드:

```bash
APP_PROCESS="agent-app"

check_process() {
    local pid
    pid=$(pgrep -f "${APP_PROCESS}" 2>/dev/null | head -1)

    if [ -z "${pid}" ]; then
        echo "[${TIMESTAMP}] [ERROR] 프로세스 '${APP_PROCESS}' 가 실행 중이지 않습니다. 모니터링을 종료합니다." | tee -a "${LOG_FILE}"
        exit 1
    fi

    echo "${pid}"
}
```

포트 Health Check 코드:

```bash
check_port() {
    local listen_check
    listen_check=$(ss -tulnp 2>/dev/null | grep "LISTEN" | grep ":${AGENT_PORT}")

    if [ -z "${listen_check}" ]; then
        echo "[${TIMESTAMP}] [ERROR] TCP ${AGENT_PORT} 포트가 LISTEN 상태가 아닙니다. 모니터링을 종료합니다." | tee -a "${LOG_FILE}"
        exit 1
    fi
}
```

명령 선택 이유:

- `pgrep -f`: 프로세스 목록에서 앱 실행 여부를 간단히 확인할 수 있고, 바이너리명 `agent-app` 기준 탐지가 가능합니다.
- `ss -tulnp`: 최신 Linux에서 `netstat`보다 권장되는 소켓 확인 도구입니다. `iproute2` 패키지에 포함되어 있고 LISTEN 포트 확인이 빠릅니다.
- 프로세스 확인과 포트 확인을 분리한 이유는 “프로세스는 살아 있지만 포트 바인딩에 실패한 상태”를 잡기 위해서입니다.

## 8. 방화벽 상태 점검과 경고 설계

방화벽 점검 코드:

```bash
check_firewall() {
    local fw_status=""

    if command -v ufw &>/dev/null; then
        fw_status=$(ufw status 2>/dev/null | grep -i "Status:" | awk '{print $2}')
        if [ -z "${fw_status}" ] && [ -r /etc/ufw/ufw.conf ]; then
            fw_status=$(awk -F= '/^ENABLED=/{print $2}' /etc/ufw/ufw.conf)
        fi
        if [ "${fw_status,,}" != "active" ] && [ "${fw_status,,}" != "yes" ]; then
            echo "[${TIMESTAMP}] [WARNING] UFW 방화벽이 비활성 상태입니다." | tee -a "${LOG_FILE}"
        fi
        return
    fi
}
```

설명:

- 방화벽 비활성은 운영상 위험하지만, 앱 프로세스/포트 장애처럼 즉시 모니터링을 중단할 조건은 아닙니다.
- 그래서 `[WARNING]`만 남기고 스크립트는 계속 진행합니다.
- 반대로 앱 프로세스 미실행이나 포트 미LISTEN은 서비스 장애이므로 `exit 1`로 종료합니다.

## 9. CPU/MEM/DISK 수집 및 로그 포맷

CPU 수집 방식:

- 1차: `top -bn1`에서 idle 값을 읽어 `100 - idle`로 계산
- fallback: `/proc/stat`을 두 번 읽어 CPU tick 차이로 계산

메모리 수집 방식:

```bash
mem_total=$(grep '^MemTotal:' /proc/meminfo | awk '{print $2}')
mem_available=$(grep '^MemAvailable:' /proc/meminfo | awk '{print $2}')
MEM_USED=$(awk "BEGIN{printf \"%.1f\", (1 - ${mem_available}/${mem_total}) * 100}")
```

디스크 수집 방식:

```bash
DISK_USED=$(df / 2>/dev/null | tail -1 | awk '{gsub(/%/,"",$5); print $5}')
```

임계값:

```text
CPU > 20%: [WARNING]
MEM > 10%: [WARNING]
DISK_USED > 80%: [WARNING]
```

로그 포맷:

```text
[YYYY-MM-DD HH:MM:SS] PID:... CPU:..% MEM:..% DISK_USED:..%
```

포맷 고정 이유:

- timestamp, PID, CPU, MEM, DISK_USED가 항상 같은 순서로 남아 사람이 읽기 쉽고 `grep`, `awk`, `tail`로 파싱하기 쉽습니다.
- cron으로 매분 누적될 때 한 줄이 하나의 측정 시점이 되므로 장애 시점과 자원 상태를 빠르게 비교할 수 있습니다.

## 10. monitor.sh 실행 결과 및 monitor.log 누적 증거

검증 명령:

```bash
docker exec b1-agent-proof-20260616-1920 bash -lc '/bin/bash /home/agent-admin/agent-app/bin/monitor.sh; tail -n 10 /var/log/agent-app/monitor.log'
```

실제 실행 결과:

```text
[2026-06-16 10:59:15] [WARNING] CPU 사용률 52.4% > 임계값 20%
[2026-06-16 10:59:15] [WARNING] MEM 사용률 15.6% > 임계값 10%
[2026-06-16 10:59:15] PID:1 CPU:52.4% MEM:15.6% DISK_USED:5%
```

누적 로그 최근 라인:

```text
[2026-06-16 10:59:01] [WARNING] MEM 사용률 15.7% > 임계값 10%
[2026-06-16 10:59:01] PID:1 CPU:52.6% MEM:15.7% DISK_USED:5%
[2026-06-16 10:59:15] [WARNING] CPU 사용률 52.4% > 임계값 20%
[2026-06-16 10:59:15] [WARNING] MEM 사용률 15.6% > 임계값 10%
[2026-06-16 10:59:15] PID:1 CPU:52.4% MEM:15.6% DISK_USED:5%
[2026-06-16 11:00:01] [WARNING] CPU 사용률 100.0% > 임계값 20%
[2026-06-16 11:00:01] [WARNING] MEM 사용률 24.4% > 임계값 10%
[2026-06-16 11:00:01] PID:1 CPU:100.0% MEM:24.4% DISK_USED:5%
```

## 11. cron 매분 실행 및 로그 증가 증거

crontab 설정:

```dockerfile
RUN echo '* * * * * /bin/bash /home/agent-admin/agent-app/bin/monitor.sh >> /var/log/agent-app/cron.log 2>&1' \
    | crontab -u agent-admin -
```

등록 확인 결과:

```text
* * * * * /bin/bash /home/agent-admin/agent-app/bin/monitor.sh >> /var/log/agent-app/cron.log 2>&1
```

1분 후 로그 증가 확인:

```text
BEFORE_AT=2026-06-16T10:59:24Z
  51 /var/log/agent-app/monitor.log
  32 /var/log/agent-app/cron.log
  83 total

AFTER_AT=2026-06-16T11:00:34Z
  54 /var/log/agent-app/monitor.log
  34 /var/log/agent-app/cron.log
  88 total
```

설명:

- `monitor.log`가 51줄에서 54줄로 증가했습니다.
- `cron.log`가 32줄에서 34줄로 증가했습니다.
- 따라서 `agent-admin` crontab의 매분 실행이 실제로 동작했습니다.

## 12. 로그 용량 관리 10MB/10개

설정값:

```bash
MAX_LOG_SIZE_MB=10
MAX_LOG_FILES=10
```

구현 코드:

```bash
rotate_log() {
    if [ ! -f "${LOG_FILE}" ]; then
        return
    fi

    local file_size_bytes
    file_size_bytes=$(stat -c%s "${LOG_FILE}" 2>/dev/null || echo 0)
    local max_bytes=$(( MAX_LOG_SIZE_MB * 1024 * 1024 ))

    if [ "${file_size_bytes}" -ge "${max_bytes}" ]; then
        for i in $(seq $(( MAX_LOG_FILES - 1 )) -1 1); do
            local src="${LOG_FILE}.${i}"
            local dst="${LOG_FILE}.$(( i + 1 ))"
            if [ -f "${src}" ]; then
                mv "${src}" "${dst}" 2>/dev/null
            fi
        done

        local oldest="${LOG_FILE}.${MAX_LOG_FILES}"
        if [ -f "${oldest}" ]; then
            rm -f "${oldest}" 2>/dev/null
        fi

        mv "${LOG_FILE}" "${LOG_FILE}.1" 2>/dev/null
    fi
}
```

동작 설명:

- `monitor.log`가 10MB 이상이면 현재 로그를 `monitor.log.1`로 이동합니다.
- 기존 `monitor.log.1`부터 `monitor.log.9`는 한 단계씩 뒤로 밀립니다.
- `monitor.log.10`을 넘는 가장 오래된 로컬 로그는 삭제됩니다.
- 제한된 로컬 디스크를 보호하기 위한 정책이며, 실무에서는 오래된 로그를 압축하거나 중앙 로그 서버/S3 같은 외부 저장소로 전송한 뒤 보존 기간이 지난 로그만 만료 처리하는 방식이 더 적합합니다.

## 13. 리다이렉션 `>`와 `>>`

- `>`: 파일을 새로 씁니다. 기존 내용은 덮어씁니다.
- `>>`: 파일 끝에 이어 씁니다. 기존 내용은 유지됩니다.

cron에는 `>>`를 사용했습니다.

```text
* * * * * /bin/bash /home/agent-admin/agent-app/bin/monitor.sh >> /var/log/agent-app/cron.log 2>&1
```

이유:

- cron은 매분 실행되므로 `>`를 쓰면 이전 실행 로그가 매번 사라집니다.
- `>>`를 써야 실행 기록이 누적되어 자동 실행 여부와 장애 시점을 확인할 수 있습니다.
- `2>&1`은 stderr를 stdout과 같은 파일로 보내 정상 출력과 에러 출력을 함께 기록하기 위한 설정입니다.

## 14. 웹 서버로 모니터링 대상이 바뀔 때 수정 포인트

웹 서버가 대상이면 다음 값을 바꿉니다.

```bash
APP_PROCESS="nginx"        # 또는 apache2, node, gunicorn 등
AGENT_PORT=80              # 또는 443, 8080 등 실제 서비스 포트
LOG_FILE="/var/log/web-monitor/monitor.log"
```

추가로 확인할 항목:

- HTTP 응답 상태 확인: `curl -fsS http://127.0.0.1:${PORT}/health`
- TLS 서비스라면 인증서 만료일 확인
- reverse proxy 뒤 서비스라면 upstream 연결 확인
- systemd 기반이면 `systemctl is-active nginx` 같은 서비스 상태 확인

핵심은 프로세스명, LISTEN 포트, 헬스체크 엔드포인트, 로그 경로를 대상 서비스에 맞게 바꾸는 것입니다.

## 15. 프로세스는 살아있는데 포트가 안 열리는 경우

원인 후보:

1. 앱이 초기화 중이거나 포트 바인딩 전에 멈춤
2. 환경 변수 `AGENT_PORT`가 잘못됨
3. 이미 다른 프로세스가 같은 포트를 사용 중
4. 앱이 `127.0.0.1`에만 바인딩하고 `0.0.0.0`에는 바인딩하지 않음
5. 키 파일/권한 문제로 앱 일부 기능이 실패
6. 방화벽이나 네트워크 namespace 문제

확인 순서:

```bash
pgrep -af agent-app
docker logs b1-agent-proof
docker exec b1-agent-proof bash -lc 'printenv | grep "^AGENT_"'
docker exec b1-agent-proof bash -lc 'ss -tulnp'
docker exec b1-agent-proof bash -lc 'ls -l /home/agent-admin/agent-app/api_keys/t_secret.key /var/log/agent-app'
docker exec b1-agent-proof bash -lc 'ufw status verbose'
```

판단 기준:

- 프로세스가 없으면 앱 실행 실패입니다.
- 프로세스는 있는데 `ss`에 15034가 없으면 앱 내부 초기화/바인딩 문제입니다.
- 15034가 `127.0.0.1`에만 있으면 외부 접근 요구사항 `0.0.0.0:15034`를 만족하지 못합니다.

## 16. 로그 급증으로 디스크가 찰 때 대응

단기 대응:

- `df -h`로 루트 파티션 사용률 확인
- `du -sh /var/log/agent-app/*`로 큰 로그 확인
- 오래된 로테이션 로그 압축 또는 외부 백업 후 제거
- 로그 레벨을 낮추거나 반복 경고 원인을 임시 완화
- 필요 시 컨테이너/서비스 재시작 전 로그 백업

중기 대응:

- `logrotate` 또는 현재 스크립트 로직으로 크기/개수 기반 로테이션 강제
- 오래된 로그 압축(`compress`) 적용
- 중앙 로그 시스템(ELK, Loki, CloudWatch, S3 등)으로 전송
- 보존 기간 정책 수립: 예를 들어 로컬 7일, 외부 30일
- 디스크 사용률 80% 이상 경고를 알림 시스템과 연동

운영 원칙:

- 로그 삭제 자체가 목적이 아니라 디스크 고갈 방지가 목적입니다.
- 필요한 로그는 압축/이관하고, 보존 기간이 지난 로그만 삭제합니다.

## 17. 제출 산출물

- `b1-1/requirements-execution-report.md`
- `b1-1/evidence-checklist.md`
- `README.md`

`requirements-execution-report.md`와 `evidence-checklist.md`에는 위 검증 결과와 수행 내역을 별도 제출 문서 형태로 정리했습니다.
