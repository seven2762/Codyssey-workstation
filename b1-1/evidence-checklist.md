# Agent App 필수 증거 자료 체크리스트

작성일: 2026-06-16
문서 보강일: 2026-06-17
검증 컨테이너: `b1-agent-proof-20260616-1920`
검증 기준 시각: UTC

## 체크리스트

| 항목 | 상태 | 확인 내역 |
| --- | --- | --- |
| SSH 포트 `20022` 변경 | 완료 | `/etc/ssh/sshd_config`에서 `Port 20022` 확인 |
| Root 원격 접속 차단 | 완료 | `/etc/ssh/sshd_config`에서 `PermitRootLogin no` 확인 |
| 방화벽 활성화 | 완료 | `ufw status verbose`에서 `Status: active` 확인 |
| 방화벽 허용 포트 제한 | 완료 | UFW inbound 허용 규칙 `20022/tcp`, `15034/tcp` 확인 |
| 계정 생성 | 완료 | `agent-admin`, `agent-dev`, `agent-test` 확인 |
| 그룹 생성 | 완료 | `agent-common`, `agent-core` 확인 |
| 그룹 멤버십 | 완료 | `agent-common`: admin/dev/test, `agent-core`: admin/dev 확인 |
| 디렉토리 구조/권한 | 완료 | 앱/업로드/API 키/bin/log 디렉토리 권한 확인 |
| ACL 설정 | 완료 | `getfacl`에서 `agent-common`, `agent-core` ACL 확인 |
| 환경 변수 구성 | 완료 | `AGENT_HOME`, `AGENT_PORT`, `AGENT_UPLOAD_DIR`, `AGENT_KEY_PATH`, `AGENT_LOG_DIR` 설정 확인 |
| 키 파일 생성 | 완료 | `$AGENT_HOME/api_keys/t_secret.key`, 내용 `agent_api_key_test` |
| 일반 계정 실행 | 완료 | Boot 로그에서 `agent-admin` 실행 확인 |
| 앱 Boot Sequence 5단계 | 완료 | `[1/5]`부터 `[5/5]`까지 모두 `[OK]` 확인 |
| `Agent READY` | 완료 | 부팅 로그에서 `Agent READY` 확인 |
| 앱 포트 LISTEN | 완료 | `0.0.0.0:15034` LISTEN 확인 |
| monitor.sh 파일 정책 | 완료 | 경로 `$AGENT_HOME/bin/monitor.sh`, 소유자 `agent-dev`, 그룹 `agent-core`, 권한 `750` 확인 |
| monitor.sh Health Check | 완료 | 프로세스/포트 비정상 시 `[ERROR]` 후 `exit 1` 로직 확인 |
| monitor.sh 방화벽 경고 | 완료 | UFW/firewalld 비활성 시 `[WARNING]`, 종료하지 않음 |
| monitor.sh 자원/임계값 | 완료 | CPU/MEM/DISK_USED 수집 및 CPU>20, MEM>10, DISK_USED>80 경고 로직 확인 |
| monitor.log 용량 관리 | 완료 | 스크립트 로직으로 최대 10MB/10개 파일 유지 |
| `monitor.sh` 실행 결과 | 완료 | CPU/MEM 경고 및 PID/자원 로그 기록 확인 |
| `monitor.log` 누적 기록 | 완료 | 최근 라인에서 `PID`, `CPU`, `MEM`, `DISK_USED` 확인 |
| crontab 매분 등록 | 완료 | `* * * * * /bin/bash .../monitor.sh` 확인 |
| cron 자동 실행 확인 | 완료 | 70초 후 `monitor.log` 51 -> 54, `cron.log` 32 -> 34 증가 확인 |

## 1. SSH 포트 변경 및 Root 원격 접속 차단

검증 명령:

```bash
docker exec b1-agent-proof-20260616-1920 bash -lc 'grep -E "^(Port|PermitRootLogin)" /etc/ssh/sshd_config; ss -tulnp | grep -E ":20022\b|:15034\b"'
```

검증 결과:

```text
Port 20022
PermitRootLogin no
PermitRootLogin no
tcp   LISTEN 0      1            0.0.0.0:15034      0.0.0.0:*
tcp   LISTEN 0      128          0.0.0.0:20022      0.0.0.0:*    users:(("sshd",pid=15,fd=3))
tcp   LISTEN 0      128             [::]:20022         [::]:*    users:(("sshd",pid=15,fd=4))
```

## 2. 방화벽 활성화 및 허용 포트

검증 명령:

```bash
docker exec b1-agent-proof-20260616-1920 bash -lc 'ufw status verbose'
```

검증 결과:

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

## 3. 계정/그룹 생성 확인

검증 명령:

```bash
docker exec b1-agent-proof-20260616-1920 bash -lc 'id agent-admin; id agent-dev; id agent-test; getent group agent-common; getent group agent-core'
```

검증 결과:

```text
uid=1001(agent-admin) gid=1003(agent-admin) groups=1003(agent-admin),1001(agent-common),1002(agent-core)
uid=1002(agent-dev) gid=1004(agent-dev) groups=1004(agent-dev),1001(agent-common),1002(agent-core)
uid=1003(agent-test) gid=1005(agent-test) groups=1005(agent-test),1001(agent-common)
agent-common:x:1001:agent-admin,agent-dev,agent-test
agent-core:x:1002:agent-admin,agent-dev
```

## 4. 디렉토리 구조 및 권한 확인

검증 명령:

```bash
docker exec b1-agent-proof-20260616-1920 bash -lc 'ls -ld /home/agent-admin/agent-app /home/agent-admin/agent-app/upload_files /home/agent-admin/agent-app/api_keys /home/agent-admin/agent-app/bin /var/log/agent-app; ls -l /home/agent-admin/agent-app/api_keys/t_secret.key /home/agent-admin/agent-app/bin/monitor.sh'
```

검증 결과:

```text
drwxr-xr-x  1 agent-admin agent-admin  4096 Jun 16 10:11 /home/agent-admin/agent-app
drwxrwx---+ 1 agent-admin agent-core   4096 Jun 16 10:11 /home/agent-admin/agent-app/api_keys
drwxr-xr-x  1 agent-admin agent-admin  4096 Jun 16 10:19 /home/agent-admin/agent-app/bin
drwxrwx---+ 1 agent-admin agent-common 4096 Jun 16 10:11 /home/agent-admin/agent-app/upload_files
drwxrwx---+ 1 agent-admin agent-core   4096 Jun 16 10:44 /var/log/agent-app
-rw-r----- 1 agent-admin agent-core   19 Jun 16 10:11 /home/agent-admin/agent-app/api_keys/t_secret.key
-rwxr-x--- 1 agent-dev   agent-core 9093 Jun 16 10:19 /home/agent-admin/agent-app/bin/monitor.sh
```

## 5. ACL 확인

검증 명령:

```bash
docker exec b1-agent-proof-20260616-1920 bash -lc 'getfacl -p /home/agent-admin/agent-app/upload_files /home/agent-admin/agent-app/api_keys /var/log/agent-app'
```

검증 결과:

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

## 6. 앱 Boot Sequence 및 Agent READY

검증 명령:

```bash
docker logs --since 2026-06-16T10:43:52Z --until 2026-06-16T10:44:45Z b1-agent-proof-20260616-1920
```

검증 결과:

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
```

확인 내용:

- 일반 계정 실행: `agent-admin`
- 환경 변수 검증: `[2/5] Verifying Environment Variables [OK]`
- 키 파일 검증: `[3/5] Checking Required Files [OK]`
- 종료 참고: 수동 종료 시 `Ctrl+C`

## 7. 환경 변수 및 키 파일

설정값:

```text
AGENT_HOME=/home/agent-admin/agent-app
AGENT_PORT=15034
AGENT_UPLOAD_DIR=/home/agent-admin/agent-app/upload_files
AGENT_KEY_PATH=/home/agent-admin/agent-app/api_keys/t_secret.key
AGENT_LOG_DIR=/var/log/agent-app
```

키 파일:

```text
경로: /home/agent-admin/agent-app/api_keys/t_secret.key
내용: agent_api_key_test
권한: -rw-r----- 1 agent-admin agent-core
```

앱 LISTEN 확인:

```text
tcp   LISTEN 0      1            0.0.0.0:15034      0.0.0.0:*
```

## 8. monitor.sh 파일 정책 및 로직 확인

파일 정책:

```text
경로: /home/agent-admin/agent-app/bin/monitor.sh
소유자: agent-dev
그룹: agent-core
권한: 750 (rwxr-x---)
cron 실행 계정: agent-admin
```

구현 확인:

```text
APP_PROCESS="agent-app"
AGENT_PORT="${AGENT_PORT:-15034}"
LOG_FILE="${AGENT_LOG_DIR}/monitor.log"
MAX_LOG_SIZE_MB=10
MAX_LOG_FILES=10
```

Health Check:

```text
프로세스 'agent-app' 미실행 시 [ERROR] 기록 후 exit 1
TCP 15034 미LISTEN 시 [ERROR] 기록 후 exit 1
```

경고 조건:

```text
UFW/firewalld 비활성: [WARNING], 종료하지 않음
CPU > 20%: [WARNING]
MEM > 10%: [WARNING]
DISK_USED > 80%: [WARNING]
```

로그 형식:

```text
[YYYY-MM-DD HH:MM:SS] PID:... CPU:..% MEM:..% DISK_USED:..%
```

로그 용량 관리:

```text
monitor.log가 10MB 이상이면 monitor.log.1부터 순환
최대 보관 파일 수: 10개
```

## 9. monitor.sh 실행 결과

검증 명령:

```bash
docker exec b1-agent-proof-20260616-1920 bash -lc '/bin/bash /home/agent-admin/agent-app/bin/monitor.sh; tail -n 10 /var/log/agent-app/monitor.log'
```

검증 결과:

```text
[2026-06-16 10:59:15] [WARNING] CPU 사용률 52.4% > 임계값 20%
[2026-06-16 10:59:15] [WARNING] MEM 사용률 15.6% > 임계값 10%
[2026-06-16 10:59:15] PID:1 CPU:52.4% MEM:15.6% DISK_USED:5%
```

확인 내용:

- 프로세스 확인: `PID:1` 기록
- 포트 확인: `15034` LISTEN 상태 별도 확인
- 리소스 확인: `CPU`, `MEM`, `DISK_USED` 기록
- 경고 확인: CPU/MEM 임계값 초과 경고 기록

## 10. monitor.log 누적 기록 최근 라인

검증 결과:

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

## 11. crontab 등록 및 자동 실행 확인

crontab 등록 확인:

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

cron 최근 라인:

```text
[2026-06-16 10:57:01] [WARNING] CPU 사용률 100.0% > 임계값 20%
[2026-06-16 10:57:01] [WARNING] MEM 사용률 24.4% > 임계값 10%
[2026-06-16 10:58:01] [WARNING] CPU 사용률 100.0% > 임계값 20%
[2026-06-16 10:58:01] [WARNING] MEM 사용률 19.4% > 임계값 10%
[2026-06-16 10:59:01] [WARNING] CPU 사용률 52.6% > 임계값 20%
[2026-06-16 10:59:01] [WARNING] MEM 사용률 15.7% > 임계값 10%
[2026-06-16 11:00:01] [WARNING] CPU 사용률 100.0% > 임계값 20%
[2026-06-16 11:00:01] [WARNING] MEM 사용률 24.4% > 임계값 10%
```
