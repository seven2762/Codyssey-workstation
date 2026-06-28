#!/bin/bash
set -uo pipefail

AGENT_HOME="${AGENT_HOME:-/home/agent-admin/agent-app}"
AGENT_PORT="${AGENT_PORT:-15034}"
AGENT_LOG_DIR="${AGENT_LOG_DIR:-/var/log/agent-app}"
MONITOR_PATH="${MONITOR_PATH:-${AGENT_HOME}/bin/monitor.sh}"
CHECK_PERMISSIONS_PATH="${CHECK_PERMISSIONS_PATH:-${AGENT_HOME}/bin/check-permissions.sh}"
CRON_WAIT_SECONDS="${CRON_WAIT_SECONDS:-70}"

if [ "${EUID}" -eq 0 ]; then
    SUDO=""
else
    SUDO="sudo"
fi

section() {
    printf '\n## %s\n' "$1"
}

run_cmd() {
    printf '\n$ %s\n' "$*"
    "$@"
}

run_shell() {
    printf '\n$ %s\n' "$1"
    bash -lc "$1"
}

run_root() {
    if [ "${EUID}" -eq 0 ]; then
        run_cmd "$@"
    else
        printf '\n$ sudo'
        printf ' %q' "$@"
        printf '\n'
        sudo "$@"
    fi
}

run_as_agent_admin() {
    if [ "${EUID}" -eq 0 ]; then
        runuser -u agent-admin -- "$@"
    else
        sudo -u agent-admin "$@"
    fi
}

show_ssh() {
    section "SSH 포트 및 root 원격 접속 차단"
    run_root grep -E "^(Port|PermitRootLogin)" /etc/ssh/sshd_config
    run_shell "ss -tulnp | grep -E ':20022\\b|:${AGENT_PORT}\\b' || true"
}

show_firewall() {
    section "방화벽 상태 및 허용 포트"
    run_root ufw status verbose
}

show_accounts() {
    section "계정/그룹 구성"
    run_cmd id agent-admin
    run_cmd id agent-dev
    run_cmd id agent-test
    run_cmd getent group agent-common
    run_cmd getent group agent-core

    section "계정별 권한 접근 결과"
    run_root /bin/bash "${CHECK_PERMISSIONS_PATH}"
}

show_boot_sequence() {
    section "Boot Sequence 및 Agent READY"
    run_shell "systemctl status agent-app --no-pager --lines=20"
    run_root journalctl -u agent-app --no-pager -n 80
    run_shell "journalctl -u agent-app --no-pager -n 300 | grep -E '\\[[1-5]/5\\]|Agent READY' || true"
}

show_monitor_health() {
    section "monitor.sh 프로세스/포트 점검 및 exit 1 확인"
    run_shell "pgrep -af agent-app || true"
    run_shell "ss -tulnp | grep -E ':${AGENT_PORT}\\b' || true"

    local tmp_dir
    tmp_dir="$(mktemp -d)"
    ${SUDO} chown agent-admin:agent-core "${tmp_dir}" 2>/dev/null || true
    ${SUDO} chmod 770 "${tmp_dir}" 2>/dev/null || true

    printf '\n$ sudo -u agent-admin env AGENT_PORT=1 AGENT_LOG_DIR=%s /bin/bash %s\n' "${tmp_dir}" "${MONITOR_PATH}"
    run_as_agent_admin env AGENT_PORT=1 AGENT_LOG_DIR="${tmp_dir}" /bin/bash "${MONITOR_PATH}"
    local exit_code=$?
    printf '$ echo $?\n%s\n' "${exit_code}"

    printf '\n$ sudo cat %s/monitor.log\n' "${tmp_dir}"
    ${SUDO} cat "${tmp_dir}/monitor.log" 2>/dev/null || true

    rm -rf "${tmp_dir}"
}

show_monitor_log() {
    section "monitor.log 누적 기록 및 지정 포맷"
    run_root tail -n 20 "${AGENT_LOG_DIR}/monitor.log"
    run_shell "grep -E '^\\[[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\\] PID:[0-9]+ CPU:[0-9.]+% MEM:[0-9.]+% DISK_USED:[0-9]+%$' '${AGENT_LOG_DIR}/monitor.log' | tail -n 5 || true"
}

show_cron_growth() {
    section "cron 매분 실행 및 monitor.log 자동 증가"
    run_root crontab -u agent-admin -l

    printf '\n$ sudo wc -l %s/monitor.log %s/cron.log\n' "${AGENT_LOG_DIR}" "${AGENT_LOG_DIR}"
    ${SUDO} wc -l "${AGENT_LOG_DIR}/monitor.log" "${AGENT_LOG_DIR}/cron.log" 2>/dev/null || true

    printf '\n[INFO] %s초 대기 후 다시 라인 수를 확인합니다.\n' "${CRON_WAIT_SECONDS}"
    sleep "${CRON_WAIT_SECONDS}"

    printf '\n$ sudo wc -l %s/monitor.log %s/cron.log\n' "${AGENT_LOG_DIR}" "${AGENT_LOG_DIR}"
    ${SUDO} wc -l "${AGENT_LOG_DIR}/monitor.log" "${AGENT_LOG_DIR}/cron.log" 2>/dev/null || true
}

show_log_rotation() {
    section "monitor.log 용량 관리 설정 및 동작 확인 방법"
    run_shell "grep -E '^(MAX_LOG_SIZE_MB|MAX_LOG_FILES)=' '${MONITOR_PATH}'"
    run_shell "grep -n 'rotate_log' '${MONITOR_PATH}'"

    local tmp_dir
    tmp_dir="$(mktemp -d)"
    ${SUDO} chown agent-admin:agent-core "${tmp_dir}" 2>/dev/null || true
    ${SUDO} chmod 770 "${tmp_dir}" 2>/dev/null || true
    truncate -s $((10 * 1024 * 1024)) "${tmp_dir}/monitor.log"
    ${SUDO} chown agent-admin:agent-core "${tmp_dir}/monitor.log" 2>/dev/null || true
    ${SUDO} chmod 660 "${tmp_dir}/monitor.log" 2>/dev/null || true

    printf '\n$ ls -lh %s\n' "${tmp_dir}"
    ls -lh "${tmp_dir}"

    printf '\n$ sudo -u agent-admin env AGENT_LOG_DIR=%s AGENT_PORT=%s /bin/bash %s\n' "${tmp_dir}" "${AGENT_PORT}" "${MONITOR_PATH}"
    run_as_agent_admin env AGENT_LOG_DIR="${tmp_dir}" AGENT_PORT="${AGENT_PORT}" /bin/bash "${MONITOR_PATH}" || true

    printf '\n$ ls -lh %s\n' "${tmp_dir}"
    ls -lh "${tmp_dir}"

    rm -rf "${tmp_dir}"
}

main() {
    show_ssh
    show_firewall
    show_accounts
    show_boot_sequence
    show_monitor_health
    show_monitor_log
    show_cron_growth
    show_log_rotation
}

main "$@"
