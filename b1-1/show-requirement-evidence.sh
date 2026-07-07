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

    # Boot Sequence는 서비스가 active 상태로 진입한 시점에 딱 한 번만 찍힌다.
    # 서비스가 오래 떠 있으면(재시작 없이) 이후 워크로드 로그에 밀려 "-n 300"
    # 같은 최근 로그 창에는 안 잡힐 수 있다. ActiveEnterTimestamp(마지막으로
    # active 가 된 정확한 시각)부터 조회하면 가동 시간과 무관하게 항상 잡힌다.
    run_shell "since=\$(systemctl show -p ActiveEnterTimestamp --value agent-app); journalctl -u agent-app --no-pager --since \"\${since}\" | grep -E '\\[[1-5]/5\\]|Agent READY' || true"
}


show_monitor_health() {
    section "monitor.sh 프로세스/포트 점검 및 exit 1 확인"
    run_shell "pgrep -af agent-app || true"
    run_shell "ss -tulnp | grep -E ':${AGENT_PORT}\\b' || true"

    local tmp_dir
    tmp_dir="$(mktemp -d)"
    ${SUDO} chown agent-admin:agent-core "${tmp_dir}" 2>/dev/null || true
    ${SUDO} chmod 770 "${tmp_dir}" 2>/dev/null || true

    local quoted_tmp_dir quoted_monitor_path
    printf -v quoted_tmp_dir '%q' "${tmp_dir}"
    printf -v quoted_monitor_path '%q' "${MONITOR_PATH}"

    printf '\n$ sudo -u agent-admin bash -lc '\''export AGENT_PORT=65000; export AGENT_LOG_DIR=%s; /bin/bash %s'\''\n' "${quoted_tmp_dir}" "${quoted_monitor_path}"
    run_as_agent_admin bash -lc "export AGENT_PORT=65000; export AGENT_LOG_DIR=${quoted_tmp_dir}; /bin/bash ${quoted_monitor_path}"
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

    local quoted_tmp_dir quoted_agent_port quoted_monitor_path
    printf -v quoted_tmp_dir '%q' "${tmp_dir}"
    printf -v quoted_agent_port '%q' "${AGENT_PORT}"
    printf -v quoted_monitor_path '%q' "${MONITOR_PATH}"

    printf '\n$ sudo -u agent-admin bash -lc '\''export AGENT_LOG_DIR=%s; export AGENT_PORT=%s; /bin/bash %s'\''\n' "${quoted_tmp_dir}" "${quoted_agent_port}" "${quoted_monitor_path}"
    run_as_agent_admin bash -lc "export AGENT_LOG_DIR=${quoted_tmp_dir}; export AGENT_PORT=${quoted_agent_port}; /bin/bash ${quoted_monitor_path}" || true

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

