#!/bin/bash
set -euo pipefail

# Provision the Agent App on an OrbStack Ubuntu machine.
# Run from the cloned repository: sudo ./provision-orbstack.sh

AGENT_HOME="${AGENT_HOME:-/home/agent-admin/agent-app}"
AGENT_PORT="${AGENT_PORT:-15034}"
AGENT_UPLOAD_DIR="${AGENT_UPLOAD_DIR:-${AGENT_HOME}/upload_files}"
AGENT_KEY_PATH="${AGENT_KEY_PATH:-${AGENT_HOME}/api_keys/t_secret.key}"
AGENT_LOG_DIR="${AGENT_LOG_DIR:-/var/log/agent-app}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYSTEMD_UNIT="/etc/systemd/system/agent-app.service"
ENV_FILE="/etc/agent-app/agent-app.env"

log() {
    echo "[INFO] $*"
}

require_root() {
    if [ "${EUID}" -ne 0 ]; then
        echo "[ERROR] root 권한으로 실행해야 합니다: sudo ./provision-orbstack.sh" >&2
        exit 1
    fi

}

require_amd64() {
    local arch
    arch="$(dpkg --print-architecture)"
    if [ "${arch}" != "amd64" ]; then
        echo "[ERROR] agent-app은 x86_64 Linux 바이너리입니다. OrbStack machine을 --arch amd64로 생성하세요." >&2
        echo "        예: orb create --arch amd64 ubuntu:noble b1-agent" >&2
        exit 1
    fi
}

install_packages() {
    log "필수 패키지 설치 중..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y \
        sudo \
        acl \
        ufw \
        iptables \
        iproute2 \
        procps \
        cron \
        bc \
        vim \
        openssh-server \
        ca-certificates
}

ensure_group() {
    local group_name="$1"
    if ! getent group "${group_name}" >/dev/null; then
        groupadd "${group_name}"
    fi
}

ensure_user() {
    local user_name="$1"
    if ! id -u "${user_name}" >/dev/null 2>&1; then
        useradd -m -s /bin/bash "${user_name}"
    fi
}

configure_accounts() {
    log "계정/그룹 구성 중..."
    ensure_group agent-common
    ensure_group agent-core

    ensure_user agent-admin
    ensure_user agent-dev
    ensure_user agent-test

    usermod -aG agent-common agent-admin
    usermod -aG agent-common agent-dev
    usermod -aG agent-common agent-test
    usermod -aG agent-core agent-admin
    usermod -aG agent-core agent-dev
}

# 그룹에 대해 접근 ACL과 기본(default) ACL을 함께 적용하는 헬퍼.
# default ACL은 이후 그 디렉토리에 생성되는 파일에도 권한이 상속되게 한다.
set_group_acl() {
    local group="$1"
    local dir="$2"
    setfacl -m "g:${group}:rwx" "${dir}"
    setfacl -d -m "g:${group}:rwx" "${dir}"
}

# 디렉토리 구조 생성 (소유자/그룹/권한 지정)
configure_directories() {
    log "디렉토리 구조 생성 중..."
    chmod 711 /home/agent-admin
    install -d -o agent-admin -g agent-admin  -m 755 "${AGENT_HOME}"
    install -d -o agent-admin -g agent-common -m 770 "${AGENT_UPLOAD_DIR}"
    install -d -o agent-admin -g agent-core   -m 770 "${AGENT_HOME}/api_keys"
    install -d -o agent-admin -g agent-admin  -m 755 "${AGENT_HOME}/bin"
    install -d -o agent-admin -g agent-core   -m 770 "${AGENT_LOG_DIR}"
}

# 앱 바이너리 및 운영 스크립트 설치 (monitor.sh는 agent-dev:agent-core 750)
install_app_files() {
    log "앱/스크립트 설치 중..."
    install -o agent-admin -g agent-admin -m 755 "${SCRIPT_DIR}/agent-app" "${AGENT_HOME}/agent-app"
    install -o agent-dev -g agent-core -m 750 "${SCRIPT_DIR}/monitor.sh" "${AGENT_HOME}/bin/monitor.sh"
    install -o agent-dev -g agent-core -m 750 "${SCRIPT_DIR}/check-permissions.sh" "${AGENT_HOME}/bin/check-permissions.sh"
    install -o agent-dev -g agent-core -m 750 "${SCRIPT_DIR}/show-requirement-evidence.sh" "${AGENT_HOME}/bin/show-requirement-evidence.sh"
}

# API 키 파일 생성 (agent-core만 읽기 가능하도록 640)
create_key_file() {
    log "API 키 파일 생성 중..."
    printf 'agent_api_key_test\n' > "${AGENT_KEY_PATH}"
    chown agent-admin:agent-core "${AGENT_KEY_PATH}"
    chmod 640 "${AGENT_KEY_PATH}"
}

# 그룹 기반 접근 통제 ACL 적용
#   공유 디렉토리: upload_files → agent-common R/W
#   보안 디렉토리: api_keys, 로그 → agent-core ONLY R/W (other 제거)
apply_acls() {
    log "ACL 적용 중..."
    chmod o-rwx "${AGENT_HOME}/api_keys" "${AGENT_LOG_DIR}"
    set_group_acl agent-common "${AGENT_UPLOAD_DIR}"
    set_group_acl agent-core   "${AGENT_HOME}/api_keys"
    set_group_acl agent-core   "${AGENT_LOG_DIR}"
}

configure_files() {
    configure_directories
    install_app_files
    create_key_file
    apply_acls
}

configure_command_links() {
    log "실행 명령 심볼릭 링크 구성 중..."
    install -d -o root -g root -m 755 /usr/local/bin

    ln -sfn "${AGENT_HOME}/bin/monitor.sh" /usr/local/bin/monitor.sh
    ln -sfn "${AGENT_HOME}/bin/check-permissions.sh" /usr/local/bin/check-permissions.sh
    ln -sfn "${AGENT_HOME}/bin/show-requirement-evidence.sh" /usr/local/bin/show-requirement-evidence.sh
}

set_or_append_sshd_config() {
    local key="$1"
    local value="$2"
    local file="/etc/ssh/sshd_config"

    if grep -Eq "^[#[:space:]]*${key}[[:space:]]+" "${file}"; then
        sed -i -E "s|^[#[:space:]]*${key}[[:space:]]+.*|${key} ${value}|" "${file}"
    else
        printf '%s %s\n' "${key}" "${value}" >> "${file}"
    fi
}

configure_ssh() {
    log "SSH 설정 중..."
    mkdir -p /var/run/sshd
    if [ ! -f /etc/ssh/sshd_config.bak.agent-app ]; then
        cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak.agent-app
    fi

    set_or_append_sshd_config Port 20022
    set_or_append_sshd_config PermitRootLogin no

    # Ubuntu 24.04는 기본이 소켓 활성화(ssh.socket)라 sshd_config의 커스텀 Port를
    # 무시하고 22번만 연다. 커스텀 포트(20022)를 쓰려면 소켓 활성화를 끄고
    # ssh.service가 sshd_config를 읽어 직접 리슨하게 해야 한다.
    # (OrbStack 접속은 ssh.socket이 아닌 자체 채널이라 꺼도 영향 없음)
    systemctl disable --now ssh.socket >/dev/null 2>&1 || true

    # LXC에서 restart 시 옛 sshd가 남아 포트를 물고 있으면 새 인스턴스가 bind에
    # 실패하고(exit 255) 유닛이 failed로 남는다. 떠도는 sshd를 정리하고 failed
    # 상태를 리셋한 뒤 재기동해, 재실행(멱등) 시에도 정상 기동되게 한다.
    pkill -x sshd 2>/dev/null || true
    systemctl reset-failed ssh >/dev/null 2>&1 || true
    systemctl enable ssh >/dev/null 2>&1 || true
    systemctl restart ssh

    if ! systemctl is-active --quiet ssh; then
        echo "[ERROR] ssh 서비스가 active 상태가 아닙니다." >&2
        systemctl status ssh --no-pager >&2 || true
        exit 1
    fi
}

configure_firewall() {
    log "UFW 방화벽 설정 중..."
    ufw --force reset
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow 20022/tcp
    ufw allow "${AGENT_PORT}/tcp"
    ufw --force enable
}

# 단일 소스인 환경 변수 파일(.env) 작성. systemd EnvironmentFile 과 monitor.sh,
# profile.d 로더가 모두 이 파일 하나를 참조한다(설정 이중화 방지).
write_env_file() {
    log "환경 변수 파일 구성 중..."
    install -d -o root -g root -m 755 /etc/agent-app
    cat > "${ENV_FILE}" <<EOF
AGENT_HOME=${AGENT_HOME}
AGENT_PORT=${AGENT_PORT}
AGENT_UPLOAD_DIR=${AGENT_UPLOAD_DIR}
AGENT_KEY_PATH=${AGENT_KEY_PATH}
AGENT_LOG_DIR=${AGENT_LOG_DIR}
EOF
    chown root:agent-core "${ENV_FILE}"
    chmod 640 "${ENV_FILE}"
}

# 로그인 셸에도 환경변수를 "고정"하는 profile.d 로더 설치.
# systemd EnvironmentFile 은 서비스 프로세스에만 값을 주입하므로, 사용자가
# 앱을 직접 실행하는 미션 방식(일반 계정 실행 → Boot Sequence → Ctrl+C)에서는
# 셸에 AGENT_* 가 없어 [2/5] Verifying Environment Variables 가 실패한다.
# 로더가 로그인 시 동일한 .env(단일 소스)를 export 하도록 한다.
# ENV_FILE 이 읽기 불가한 계정(agent-core 미소속)은 -r 가드로 조용히 건너뛴다.
install_login_env_loader() {
    log "로그인 셸 환경변수 로더 설치 중..."
    cat > /etc/profile.d/agent-app.sh <<EOF
# Agent App 환경변수 로더 (단일 소스: ${ENV_FILE})
if [ -r "${ENV_FILE}" ]; then
    set -a
    . "${ENV_FILE}"
    set +a
fi
EOF
    chmod 644 /etc/profile.d/agent-app.sh
}

configure_environment() {
    write_env_file
    install_login_env_loader
}

configure_systemd() {
    log "agent-app systemd 서비스 구성 중..."
    cat > "${SYSTEMD_UNIT}" <<EOF
[Unit]
Description=Agent App
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=agent-admin
Group=agent-admin
EnvironmentFile=${ENV_FILE}
WorkingDirectory=${AGENT_HOME}
ExecStart=${AGENT_HOME}/agent-app
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable agent-app
    systemctl restart agent-app
}

configure_cron() {
    log "cron 구성 중..."
    systemctl enable cron >/dev/null 2>&1 || true

    # OrbStack/LXC에서 provision 중 cron 인스턴스가 충돌해 유닛이 failed로
    # 남고(떠도는 cron 프로세스는 살아있는) 경우가 있다. 이 상태면 재부팅 시
    # systemd가 cron을 안 살려 자동 실행이 멈춘다. 떠도는 인스턴스를 정리하고
    # failed 상태를 리셋한 뒤 다시 띄워, systemd가 단일 cron을 정상 추적하게 한다.
    pkill -x cron 2>/dev/null || true
    systemctl reset-failed cron 2>/dev/null || true
    systemctl restart cron

    # 정상 기동 확인 (실패하면 provision을 멈춰 문제를 조기에 드러낸다)
    if ! systemctl is-active --quiet cron; then
        echo "[ERROR] cron 서비스가 active 상태가 아닙니다. 자동 실행이 동작하지 않습니다." >&2
        systemctl status cron --no-pager >&2 || true
        exit 1
    fi

    echo "* * * * * /bin/bash ${AGENT_HOME}/bin/monitor.sh >> ${AGENT_LOG_DIR}/cron.log 2>&1" | crontab -u agent-admin -
}

print_summary() {
    cat <<EOF

======================================
  Agent App OrbStack VM 설정 완료
======================================
AGENT_HOME       = ${AGENT_HOME}
AGENT_PORT       = ${AGENT_PORT}
AGENT_UPLOAD_DIR = ${AGENT_UPLOAD_DIR}
AGENT_KEY_PATH   = ${AGENT_KEY_PATH}
AGENT_LOG_DIR    = ${AGENT_LOG_DIR}

검증:
  sudo ./verify-orbstack.sh
  sudo show-requirement-evidence.sh
  sudo check-permissions.sh
  systemctl status agent-app --no-pager
  ufw status verbose
EOF
}

main() {
    require_root
    require_amd64
    install_packages
    configure_accounts
    configure_files
    configure_command_links
    configure_ssh
    configure_firewall
    configure_environment
    configure_systemd
    configure_cron
    print_summary
}

main "$@"
