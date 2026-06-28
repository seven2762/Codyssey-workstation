# b1-1 Agent App

Agent App 실행 환경을 **OrbStack Ubuntu Linux machine** 위에 구성하는 프로젝트입니다.

미션의 핵심은 서버 운영 환경을 직접 구축하는 것이므로, SSH/UFW/계정/권한/ACL/cron/로그/리소스 관제를 컨테이너 내부에서 흉내내지 않고 VM의 OS 레벨 설정으로 구성합니다.

## 왜 Docker가 아닌 OrbStack VM인가

Docker 컨테이너에서 UFW를 동작시키려면 보통 다음 권한이 필요합니다.

```bash
--cap-add NET_ADMIN --cap-add NET_RAW
```

이 방식은 앱 컨테이너에 네트워크 관리 권한을 추가로 부여합니다. 컨테이너는 원래 앱 프로세스를 제한된 권한으로 격리해 실행하는 단위인데, `NET_ADMIN`은 방화벽/라우팅/네트워크 인터페이스 조작 권한을 열어 줍니다. 즉 “서버 방화벽을 구성했다”기보다 “권한을 크게 높인 컨테이너 안에서 방화벽을 흉내냈다”에 가까워집니다.

VM에서는 UFW, SSH, cron, 사용자/그룹, ACL이 실제 OS의 운영 관리 대상입니다. 그래서 다중 사용자 서버 운영과 네트워크 보안 설정을 익히는 이 미션에는 VM 방식이 더 자연스럽습니다.

## 파일

| 파일 | 설명 |
| --- | --- |
| `b1-1/provision-orbstack.sh` | OrbStack Ubuntu machine 안에서 서버 환경을 구성하는 프로비저닝 스크립트 |
| `b1-1/verify-orbstack.sh` | SSH/UFW/계정/권한/ACL/service/cron/monitor 로그 검증 스크립트 |
| `b1-1/check-permissions.sh` | `agent-admin`, `agent-dev`, `agent-test` 계정별 권한 검증 스크립트 |
| `b1-1/show-requirement-evidence.sh` | 필수 평가 항목별 검증 명령과 출력을 모아 보여주는 증거 수집 스크립트 |
| `b1-1/bootstrap-orbstack.sh` | 저장소 clone/update 후 `b1-1/provision-orbstack.sh`를 실행하는 bootstrap 스크립트 |
| `b1-1/orbstack-machine.sh` | macOS 호스트에서 OrbStack machine 생성/시작/접속을 처리하는 스크립트 |
| `b1-1/monitor.sh` | 프로세스/포트/방화벽/CPU/MEM/DISK 점검 및 로그 기록 |
| `b1-1/agent-app` | 제공된 x86_64 Linux 실행 바이너리 |
| `b1-1/requirements-execution-report.md` | 수행 내역서 |
| `b1-1/evidence-checklist.md` | 필수 증거 자료 체크리스트 |

## OrbStack Machine 생성

`agent-app`은 x86_64 Linux 바이너리이므로 Apple Silicon 환경에서도 amd64 machine으로 생성합니다.

macOS 호스트에서 스크립트로 생성/시작/접속까지 한 번에 처리할 수 있습니다.

```bash
./b1-1/orbstack-machine.sh
```

개별 명령이 필요하면 다음처럼 실행합니다.

```bash
./b1-1/orbstack-machine.sh create
./b1-1/orbstack-machine.sh start
./b1-1/orbstack-machine.sh shell
```

시연용으로 기존 machine을 지우고 새로 만든 뒤 bootstrap/provision까지 한 번에 실행하려면 macOS 호스트에서 다음 명령을 실행합니다.

```bash
./b1-1/orbstack-machine.sh reset-demo
```

```bash
orb create --arch amd64 ubuntu:noble b1-agent
orb -m b1-agent
```

## 설치

OrbStack machine 안에서 bootstrap 스크립트를 내려받아 실행합니다. 스크립트가 저장소를 clone/update하고 프로비저닝까지 이어서 실행합니다.
`bootstrap-orbstack.sh`의 역할은 VM 생성이 아니라, 이미 접속한 Ubuntu machine 안에서 `git`을 준비하고 이 저장소의 `b1-1` 브랜치를 받은 뒤 `b1-1/provision-orbstack.sh`를 실행하는 것입니다.

```bash
sudo apt-get update
sudo apt-get install -y curl
curl -fsSL https://raw.githubusercontent.com/seven2762/Codyssey-workstation/b1-1/b1-1/bootstrap-orbstack.sh -o bootstrap-orbstack.sh
chmod +x bootstrap-orbstack.sh
./bootstrap-orbstack.sh
```

위 설치 절차만 한 줄로 실행하려면 OrbStack machine 안에서 다음 명령을 사용할 수 있습니다.

```bash
sudo apt-get update && sudo apt-get install -y curl && bash <(curl -fsSL https://raw.githubusercontent.com/seven2762/Codyssey-workstation/b1-1/b1-1/bootstrap-orbstack.sh)
```

주의: `provision-orbstack.sh`는 미션 전용 machine을 전제로 `ufw --force reset`을 실행합니다. 기존 서비스가 같이 떠 있는 공용 서버나 운영 VM에서는 실행하지 마세요.

기본 clone 경로는 `${HOME}/Codyssey-workstation`입니다. 경로를 바꾸려면 다음처럼 실행합니다.

```bash
TARGET_DIR=/opt/Codyssey-workstation ./bootstrap-orbstack.sh
```

스크립트가 수행하는 작업:

- Ubuntu 패키지 설치: `openssh-server`, `ufw`, `acl`, `cron`, `iproute2`, `procps`, `bc`
- SSH 포트 `20022` 설정 및 root 원격 접속 차단
- UFW 활성화, inbound 기본 차단, `20022/tcp`, `15034/tcp`만 허용
- `agent-admin`, `agent-dev`, `agent-test` 계정 생성
- `agent-common`, `agent-core` 그룹 생성 및 멤버십 설정
- 앱/업로드/API 키/bin/log 디렉토리 생성
- 디렉토리 권한과 ACL 설정
- `/etc/agent-app/agent-app.env` 환경 변수 파일 생성
- `agent-app`을 `agent-admin` 계정의 `systemd` 서비스로 실행
- `agent-admin` crontab에 `monitor.sh` 매분 실행 등록

## 검증

```bash
sudo ./verify-orbstack.sh
```

필수 평가 항목별 검증 명령과 출력을 한 번에 보려면 다음 명령을 실행합니다. cron 자동 증가 확인 때문에 기본적으로 70초 대기합니다.

```bash
sudo /home/agent-admin/agent-app/bin/show-requirement-evidence.sh
```

대기 시간을 줄여 빠르게 출력만 확인하려면 다음처럼 실행할 수 있습니다.

```bash
sudo CRON_WAIT_SECONDS=5 /home/agent-admin/agent-app/bin/show-requirement-evidence.sh
```

개별 확인 명령:

```bash
systemctl status agent-app --no-pager
sudo ufw status verbose
sudo crontab -u agent-admin -l
sudo tail -n 20 /var/log/agent-app/monitor.log
ss -tulnp | grep -E ':20022\b|:15034\b'
```

계정별 권한만 따로 검증하려면 다음 명령을 실행합니다.

```bash
sudo /home/agent-admin/agent-app/bin/check-permissions.sh
```

기대 결과:

```text
agent-admin: upload/key/log/monitor 접근 OK
agent-dev: upload/key/log/monitor 접근 OK
agent-test: upload 접근 OK, key/log/monitor 접근 DENIED
```

## 주요 경로

| 항목 | 경로 |
| --- | --- |
| 앱 홈 | `/home/agent-admin/agent-app` |
| 앱 바이너리 | `/home/agent-admin/agent-app/agent-app` |
| 업로드 디렉토리 | `/home/agent-admin/agent-app/upload_files` |
| API 키 | `/home/agent-admin/agent-app/api_keys/t_secret.key` |
| 모니터링 스크립트 | `/home/agent-admin/agent-app/bin/monitor.sh` |
| 로그 디렉토리 | `/var/log/agent-app` |
| 환경 변수 파일 | `/etc/agent-app/agent-app.env` |
| systemd 서비스 | `/etc/systemd/system/agent-app.service` |

## 운영 모델

앱은 root가 아닌 `agent-admin` 계정으로 실행됩니다.

```bash
systemctl status agent-app --no-pager
sudo journalctl -u agent-app -f
sudo systemctl restart agent-app
```

`monitor.sh`는 매분 cron으로 실행되며 다음을 확인합니다.

- `agent-app` 프로세스 실행 여부
- TCP `15034` LISTEN 여부
- UFW/firewalld 활성화 여부
- CPU/MEM/DISK 사용률
- 임계값 초과 경고
- `/var/log/agent-app/monitor.log` 용량 로테이션
