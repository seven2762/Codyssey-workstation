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

configure_files() {
    log "디렉토리/권한/ACL 구성 중..."
    install -d -o agent-admin -g agent-admin -m 755 "${AGENT_HOME}"
    install -d -o agent-admin -g agent-common -m 770 "${AGENT_UPLOAD_DIR}"
    install -d -o agent-admin -g agent-core -m 770 "${AGENT_HOME}/api_keys"
    install -d -o agent-admin -g agent-admin -m 755 "${AGENT_HOME}/bin"
    install -d -o agent-admin -g agent-core -m 770 "${AGENT_LOG_DIR}"

    install -o agent-admin -g agent-admin -m 755 "${SCRIPT_DIR}/agent-app" "${AGENT_HOME}/agent-app"
    install -o agent-dev -g agent-core -m 750 "${SCRIPT_DIR}/monitor.sh" "${AGENT_HOME}/bin/monitor.sh"

    printf 'agent_api_key_test\n' > "${AGENT_KEY_PATH}"
    chown agent-admin:agent-core "${AGENT_KEY_PATH}"
    chmod 640 "${AGENT_KEY_PATH}"

    chmod o-rwx "${AGENT_HOME}/api_keys" "${AGENT_LOG_DIR}"

    setfacl -m g:agent-common:rwx "${AGENT_UPLOAD_DIR}"
    setfacl -d -m g:agent-common:rwx "${AGENT_UPLOAD_DIR}"
    setfacl -m g:agent-core:rwx "${AGENT_HOME}/api_keys"
    setfacl -d -m g:agent-core:rwx "${AGENT_HOME}/api_keys"
    setfacl -m g:agent-core:rwx "${AGENT_LOG_DIR}"
    setfacl -d -m g:agent-core:rwx "${AGENT_LOG_DIR}"
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

    systemctl enable ssh >/dev/null 2>&1 || true
    systemctl restart ssh
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

configure_environment() {
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
    systemctl restart cron
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
    configure_ssh
    configure_firewall
    configure_environment
    configure_systemd
    configure_cron
    print_summary
}

main "$@"
