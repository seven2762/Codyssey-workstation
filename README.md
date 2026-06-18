# b1-1 Agent App

Agent App 실행 환경을 Docker 컨테이너로 구성한 과제 프로젝트입니다.

## 구성 파일

| 파일 | 설명 |
| --- | --- |
| `b1-1/Dockerfile` | Ubuntu 24.04 기반 실행 환경, SSH/UFW/계정/권한/cron 구성 |
| `b1-1/entrypoint.sh` | SSH, cron, UFW 설정 후 `agent-admin` 계정으로 앱 실행 |
| `b1-1/monitor.sh` | 프로세스/포트/방화벽/자원 상태 점검 및 로그 기록 |
| `b1-1/agent-app` | 제공된 x86_64 Linux 실행 바이너리 |
| `b1-1/requirements-execution-report.md` | 요구사항 수행 내역서 |
| `b1-1/evidence-checklist.md` | 필수 증거 자료 체크리스트 |

## 빌드

`agent-app`은 x86_64 ELF 바이너리이므로 Apple Silicon 환경에서도 `linux/amd64` 플랫폼을 명시합니다.

```bash
cd b1-1
docker build --platform linux/amd64 -t b1-agent-app:proof .
```

## 실행

```bash
docker run --platform linux/amd64 \
  --cap-add NET_ADMIN --cap-add NET_RAW \
  -d \
  --name b1-agent-proof \
  -p 20022:20022 \
  -p 15034:15034 \
  b1-agent-app:proof
```

## 주요 검증 명령

부팅 로그:

```bash
docker logs b1-agent-proof
```

SSH 설정:

```bash
docker exec b1-agent-proof bash -lc 'grep -E "^(Port|PermitRootLogin)" /etc/ssh/sshd_config'
```

포트 LISTEN:

```bash
docker exec b1-agent-proof bash -lc 'ss -tulnp | grep -E ":20022\b|:15034\b"'
```

UFW:

```bash
docker exec b1-agent-proof bash -lc 'ufw status verbose'
```

계정/그룹:

```bash
docker exec b1-agent-proof bash -lc 'id agent-admin; id agent-dev; id agent-test; getent group agent-common; getent group agent-core'
```

권한/ACL:

```bash
docker exec b1-agent-proof bash -lc 'ls -ld /home/agent-admin/agent-app /home/agent-admin/agent-app/upload_files /home/agent-admin/agent-app/api_keys /var/log/agent-app'
docker exec b1-agent-proof bash -lc 'getfacl -p /home/agent-admin/agent-app/upload_files /home/agent-admin/agent-app/api_keys /var/log/agent-app'
```

monitor 실행 및 로그:

```bash
docker exec b1-agent-proof bash -lc '/bin/bash /home/agent-admin/agent-app/bin/monitor.sh'
docker exec b1-agent-proof bash -lc 'tail -n 20 /var/log/agent-app/monitor.log'
```

cron 등록 및 자동 실행:

```bash
docker exec b1-agent-proof bash -lc 'crontab -u agent-admin -l'
docker exec b1-agent-proof bash -lc 'wc -l /var/log/agent-app/monitor.log /var/log/agent-app/cron.log; sleep 70; wc -l /var/log/agent-app/monitor.log /var/log/agent-app/cron.log'
```

## 종료

```bash
docker stop b1-agent-proof
docker rm b1-agent-proof
```
