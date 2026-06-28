#!/bin/bash
set -euo pipefail

AGENT_HOME="${AGENT_HOME:-/home/agent-admin/agent-app}"
AGENT_PORT="${AGENT_PORT:-15034}"
AGENT_LOG_DIR="${AGENT_LOG_DIR:-/var/log/agent-app}"

if [ "${EUID}" -eq 0 ]; then
    SUDO=""
else
    SUDO="sudo"
fi

section() {
    printf '\n## %s\n' "$1"
}

run_as_agent_admin() {
    if [ "${EUID}" -eq 0 ]; then
        runuser -u agent-admin -- "$@"
    else
        sudo -u agent-admin "$@"
    fi
}

section "SSH 설정"
${SUDO} grep -E "^(Port|PermitRootLogin)" /etc/ssh/sshd_config
ss -tulnp | grep -E ":20022\b|:${AGENT_PORT}\b"

section "방화벽"
${SUDO} ufw status verbose

section "계정/그룹"
id agent-admin
id agent-dev
id agent-test
getent group agent-common
getent group agent-core

section "디렉토리/권한"
${SUDO} ls -ld \
    "${AGENT_HOME}" \
    "${AGENT_HOME}/upload_files" \
    "${AGENT_HOME}/api_keys" \
    "${AGENT_HOME}/bin" \
    "${AGENT_LOG_DIR}"
${SUDO} ls -l \
    "${AGENT_HOME}/api_keys/t_secret.key" \
    "${AGENT_HOME}/bin/monitor.sh"

section "ACL"
${SUDO} getfacl -p \
    "${AGENT_HOME}/upload_files" \
    "${AGENT_HOME}/api_keys" \
    "${AGENT_LOG_DIR}"

section "서비스"
systemctl is-active agent-app
systemctl status agent-app --no-pager --lines=20

section "cron"
${SUDO} crontab -u agent-admin -l

section "monitor.sh 수동 실행"
run_as_agent_admin /bin/bash "${AGENT_HOME}/bin/monitor.sh"
${SUDO} tail -n 10 "${AGENT_LOG_DIR}/monitor.log"
