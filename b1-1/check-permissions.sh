#!/bin/bash
set -euo pipefail

AGENT_HOME="${AGENT_HOME:-/home/agent-admin/agent-app}"
AGENT_UPLOAD_DIR="${AGENT_UPLOAD_DIR:-${AGENT_HOME}/upload_files}"
AGENT_KEY_PATH="${AGENT_KEY_PATH:-${AGENT_HOME}/api_keys/t_secret.key}"
AGENT_LOG_DIR="${AGENT_LOG_DIR:-/var/log/agent-app}"
MONITOR_PATH="${MONITOR_PATH:-${AGENT_HOME}/bin/monitor.sh}"

FAILURES=0

section() {
    printf '\n## %s\n' "$1"
}

require_root() {
    if [ "${EUID}" -ne 0 ]; then
        echo "[ERROR] root 권한으로 실행해야 합니다: sudo ./check-permissions.sh" >&2
        exit 1
    fi
}

record_result() {
    local label="$1"
    local expected="$2"
    local actual="$3"

    if [ "${expected}" = "${actual}" ]; then
        printf '[PASS] %-38s expected=%-7s actual=%s\n' "${label}" "${expected}" "${actual}"
    else
        printf '[FAIL] %-38s expected=%-7s actual=%s\n' "${label}" "${expected}" "${actual}"
        FAILURES=$((FAILURES + 1))
    fi
}

expect_group_member() {
    local user_name="$1"
    local group_name="$2"
    local expected="$3"
    local actual="DENIED"

    if id -nG "${user_name}" | tr ' ' '\n' | grep -qx "${group_name}"; then
        actual="OK"
    fi

    record_result "${user_name} in ${group_name}" "${expected}" "${actual}"
}

can_write_in_dir() {
    local user_name="$1"
    local dir_path="$2"

    runuser -u "${user_name}" -- bash -c '
        dir_path="$1"
        tmp_file="${dir_path}/.permission-check-$(id -un)-$$"
        printf "permission-check\n" > "${tmp_file}" && rm -f "${tmp_file}"
    ' _ "${dir_path}" >/dev/null 2>&1
}

can_read_file() {
    local user_name="$1"
    local file_path="$2"

    runuser -u "${user_name}" -- test -r "${file_path}" >/dev/null 2>&1
}

can_write_in_log_dir() {
    local user_name="$1"

    can_write_in_dir "${user_name}" "${AGENT_LOG_DIR}"
}

can_execute_file() {
    local user_name="$1"
    local file_path="$2"

    runuser -u "${user_name}" -- test -x "${file_path}" >/dev/null 2>&1
}

check_access() {
    local user_name="$1"
    local action="$2"
    local expected="$3"
    local actual="DENIED"

    if "${action}" "${user_name}"; then
        actual="OK"
    fi

    record_result "${user_name} ${action}" "${expected}" "${actual}"
}

upload_write() {
    can_write_in_dir "$1" "${AGENT_UPLOAD_DIR}"
}

key_read() {
    can_read_file "$1" "${AGENT_KEY_PATH}"
}

log_write() {
    can_write_in_log_dir "$1"
}

monitor_execute() {
    can_execute_file "$1" "${MONITOR_PATH}"
}

print_paths() {
    section "검증 경로"
    printf 'AGENT_HOME       = %s\n' "${AGENT_HOME}"
    printf 'AGENT_UPLOAD_DIR = %s\n' "${AGENT_UPLOAD_DIR}"
    printf 'AGENT_KEY_PATH   = %s\n' "${AGENT_KEY_PATH}"
    printf 'AGENT_LOG_DIR    = %s\n' "${AGENT_LOG_DIR}"
    printf 'MONITOR_PATH     = %s\n' "${MONITOR_PATH}"
}

check_groups() {
    section "그룹 멤버십"
    id agent-admin
    id agent-dev
    id agent-test

    expect_group_member agent-admin agent-common OK
    expect_group_member agent-admin agent-core OK
    expect_group_member agent-dev agent-common OK
    expect_group_member agent-dev agent-core OK
    expect_group_member agent-test agent-common OK
    expect_group_member agent-test agent-core DENIED
}

check_permissions() {
    section "권한 접근 결과"

    check_access agent-admin upload_write OK
    check_access agent-admin key_read OK
    check_access agent-admin log_write OK
    check_access agent-admin monitor_execute OK

    check_access agent-dev upload_write OK
    check_access agent-dev key_read OK
    check_access agent-dev log_write OK
    check_access agent-dev monitor_execute OK

    check_access agent-test upload_write OK
    check_access agent-test key_read DENIED
    check_access agent-test log_write DENIED
    check_access agent-test monitor_execute DENIED
}

print_summary() {
    section "요약"
    if [ "${FAILURES}" -eq 0 ]; then
        echo "권한 검증 통과"
        exit 0
    fi

    echo "권한 검증 실패: ${FAILURES}개 항목"
    exit 1
}

main() {
    require_root
    print_paths
    check_groups
    check_permissions
    print_summary
}

main "$@"
