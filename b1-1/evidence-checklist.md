# Agent App 필수 증거 자료 체크리스트

작성일: 2026-06-16
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
| 앱 Boot Sequence 5단계 | 완료 | `[1/5]`부터 `[5/5]`까지 모두 `[OK]` 확인 |
| `Agent READY` | 완료 | 부팅 로그에서 `Agent READY` 확인 |
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

## 7. monitor.sh 실행 결과

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

## 8. monitor.log 누적 기록 최근 라인

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

## 9. crontab 등록 및 자동 실행 확인

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

