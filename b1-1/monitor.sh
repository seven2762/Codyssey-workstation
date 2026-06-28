#!/bin/bash
# =============================================================================
# monitor.sh - Agent App 시스템 상태 수집 및 로깅 스크립트
# 소유자: agent-dev / 그룹: agent-core / 권한: 750
# cron 실행 계정: agent-admin
# =============================================================================

# ── 환경 변수 기본값 설정 ──────────────────────────────────────────────────
AGENT_HOME="${AGENT_HOME:-/home/agent-admin/agent-app}"
AGENT_PORT="${AGENT_PORT:-15034}"
AGENT_LOG_DIR="${AGENT_LOG_DIR:-/var/log/agent-app}"
LOG_FILE="${AGENT_LOG_DIR}/monitor.log"
APP_PROCESS="agent-app"

# logrotate 미사용 시 스크립트 자체 로그 용량 관리 설정
MAX_LOG_SIZE_MB=10
MAX_LOG_FILES=10

# ── 타임스탬프 ────────────────────────────────────────────────────────────
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# =============================================================================
# 함수 정의
# =============================================================================

# 로그 디렉토리 확인
check_log_dir() {
    if [ ! -d "${AGENT_LOG_DIR}" ]; then
        mkdir -p "${AGENT_LOG_DIR}" 2>/dev/null
        if [ $? -ne 0 ]; then
            echo "[${TIMESTAMP}] [ERROR] 로그 디렉토리 생성 실패: ${AGENT_LOG_DIR}" >&2
            exit 1
        fi
    fi
}

# ── 로그 파일 용량 관리 (최대 10MB / 10개 파일 유지) ─────────────────────
rotate_log() {
    if [ ! -f "${LOG_FILE}" ]; then
        return
    fi

    local file_size_bytes
    file_size_bytes=$(stat -c%s "${LOG_FILE}" 2>/dev/null || echo 0)
    local max_bytes=$(( MAX_LOG_SIZE_MB * 1024 * 1024 ))

    if [ "${file_size_bytes}" -ge "${max_bytes}" ]; then
        # 최대 개수 초과 파일 삭제
        local oldest="${LOG_FILE}.${MAX_LOG_FILES}"
        if [ -f "${oldest}" ]; then
            rm -f "${oldest}" 2>/dev/null
        fi

        # 기존 로테이션 파일들을 한 단계씩 밀기
        for i in $(seq $(( MAX_LOG_FILES - 1 )) -1 1); do
            local src="${LOG_FILE}.${i}"
            local dst="${LOG_FILE}.$(( i + 1 ))"
            if [ -f "${src}" ]; then
                mv "${src}" "${dst}" 2>/dev/null
            fi
        done

        # 현재 로그를 .1로 이동
        mv "${LOG_FILE}" "${LOG_FILE}.1" 2>/dev/null
    fi
}

# =============================================================================
# [1] Health Check - 프로세스 확인 (실패 시 exit 1)
# =============================================================================
check_process() {
    local pid
    pid=$(pgrep -f "${APP_PROCESS}" 2>/dev/null | head -1)

    if [ -z "${pid}" ]; then
        echo "[${TIMESTAMP}] [ERROR] 프로세스 '${APP_PROCESS}' 가 실행 중이지 않습니다. 모니터링을 종료합니다." | tee -a "${LOG_FILE}"
        exit 1
    fi

    echo "${pid}"
}

# =============================================================================
# [2] Health Check - 포트 LISTEN 확인 (실패 시 exit 1)
# =============================================================================
check_port() {
    local listen_check
    listen_check=$(ss -tulnp 2>/dev/null | grep "LISTEN" | grep -E ":${AGENT_PORT}\b")

    if [ -z "${listen_check}" ]; then
        echo "[${TIMESTAMP}] [ERROR] TCP ${AGENT_PORT} 포트가 LISTEN 상태가 아닙니다. 모니터링을 종료합니다." | tee -a "${LOG_FILE}"
        exit 1
    fi
}

# =============================================================================
# [3] 방화벽 상태 점검 (경고만 출력, 종료하지 않음)
# =============================================================================
check_firewall() {
    local fw_status=""

    # UFW 확인
    if command -v ufw &>/dev/null; then
        fw_status=$(ufw status 2>/dev/null | grep -i "Status:" | awk '{print $2}')
        if [ -z "${fw_status}" ] && [ -r /etc/ufw/ufw.conf ]; then
            fw_status=$(awk -F= '/^ENABLED=/{print $2}' /etc/ufw/ufw.conf)
        fi
        if [ "${fw_status,,}" != "active" ] && [ "${fw_status,,}" != "yes" ]; then
            echo "[${TIMESTAMP}] [WARNING] UFW 방화벽이 비활성 상태입니다." | tee -a "${LOG_FILE}"
        fi
        return
    fi

    # firewalld 확인
    if command -v firewall-cmd &>/dev/null; then
        fw_status=$(firewall-cmd --state 2>/dev/null)
        if [ "${fw_status}" != "running" ]; then
            echo "[${TIMESTAMP}] [WARNING] firewalld 방화벽이 비활성 상태입니다." | tee -a "${LOG_FILE}"
        fi
        return
    fi

    # 방화벽 미설치
    echo "[${TIMESTAMP}] [WARNING] 방화벽(UFW/firewalld)이 설치되어 있지 않습니다." | tee -a "${LOG_FILE}"
}

# =============================================================================
# [4] 자원 수집 - CPU / MEM / DISK
# =============================================================================
collect_resources() {
    # CPU 사용률 (%) - idle 값을 이용해 사용률 계산
    local cpu_idle
    cpu_idle=$(top -bn1 2>/dev/null | grep "Cpu(s)" | awk '{print $8}' | tr -d '%,')
    # top 출력 형식이 다를 경우 대체 방법
    if [ -z "${cpu_idle}" ]; then
        cpu_idle=$(top -bn1 2>/dev/null | grep -E "^%?Cpu" | sed 's/.*,\s*\([0-9.]*\)\s*id.*/\1/')
    fi
    local cpu_used
    if [ -n "${cpu_idle}" ]; then
        cpu_used=$(echo "100 - ${cpu_idle}" | bc 2>/dev/null || awk "BEGIN{printf \"%.1f\", 100 - ${cpu_idle}}")
    else
        # fallback: /proc/stat 활용
        local cpu_line1 cpu_line2
        cpu_line1=$(grep '^cpu ' /proc/stat)
        sleep 0.5
        cpu_line2=$(grep '^cpu ' /proc/stat)
        local idle1 idle2 total1 total2
        idle1=$(echo "${cpu_line1}" | awk '{print $5}')
        idle2=$(echo "${cpu_line2}" | awk '{print $5}')
        total1=$(echo "${cpu_line1}" | awk '{print $2+$3+$4+$5+$6+$7+$8}')
        total2=$(echo "${cpu_line2}" | awk '{print $2+$3+$4+$5+$6+$7+$8}')
        local diff_idle=$(( idle2 - idle1 ))
        local diff_total=$(( total2 - total1 ))
        if [ "${diff_total}" -gt 0 ]; then
            cpu_used=$(awk "BEGIN{printf \"%.1f\", (1 - ${diff_idle}/${diff_total}) * 100}")
        else
            cpu_used="0.0"
        fi
    fi
    CPU_USED="${cpu_used:-0.0}"

    # 메모리 사용률 (%)
    local mem_total mem_available
    mem_total=$(grep '^MemTotal:' /proc/meminfo | awk '{print $2}')
    mem_available=$(grep '^MemAvailable:' /proc/meminfo | awk '{print $2}')
    if [ -n "${mem_total}" ] && [ "${mem_total}" -gt 0 ]; then
        MEM_USED=$(awk "BEGIN{printf \"%.1f\", (1 - ${mem_available}/${mem_total}) * 100}")
    else
        MEM_USED="0.0"
    fi

    # 디스크 사용률 (Root partition, %)
    DISK_USED=$(df / 2>/dev/null | tail -1 | awk '{gsub(/%/,"",$5); print $5}')
    DISK_USED="${DISK_USED:-0}"
}

# =============================================================================
# [5] 임계값 경고 출력 (종료하지 않음)
# =============================================================================
check_thresholds() {
    local cpu_int
    cpu_int=$(echo "${CPU_USED}" | cut -d'.' -f1)

    local mem_int
    mem_int=$(echo "${MEM_USED}" | cut -d'.' -f1)

    local disk_int
    disk_int=$(echo "${DISK_USED}" | cut -d'.' -f1)

    if [ "${cpu_int}" -gt 20 ] 2>/dev/null; then
        echo "[${TIMESTAMP}] [WARNING] CPU 사용률 ${CPU_USED}% > 임계값 20%" | tee -a "${LOG_FILE}"
    fi

    if [ "${mem_int}" -gt 10 ] 2>/dev/null; then
        echo "[${TIMESTAMP}] [WARNING] MEM 사용률 ${MEM_USED}% > 임계값 10%" | tee -a "${LOG_FILE}"
    fi

    if [ "${disk_int}" -gt 80 ] 2>/dev/null; then
        echo "[${TIMESTAMP}] [WARNING] DISK 사용률 ${DISK_USED}% > 임계값 80%" | tee -a "${LOG_FILE}"
    fi
}

# =============================================================================
# [6] 로그 기록
# 포맷: [YYYY-MM-DD HH:MM:SS] PID:... CPU:..% MEM:..% DISK_USED:..%
# =============================================================================
write_log() {
    local pid="${1}"
    echo "[${TIMESTAMP}] PID:${pid} CPU:${CPU_USED}% MEM:${MEM_USED}% DISK_USED:${DISK_USED}%" >> "${LOG_FILE}"
}

# =============================================================================
# MAIN
# =============================================================================
main() {
    # 로그 디렉토리 확인 및 생성
    check_log_dir

    # 로그 로테이션 (용량 초과 시)
    rotate_log

    # [1] 프로세스 Health Check
    APP_PID=$(check_process)

    # [2] 포트 Health Check
    check_port

    # [3] 방화벽 상태 점검 (경고)
    check_firewall

    # [4] 자원 수집
    collect_resources

    # [5] 임계값 경고 출력
    check_thresholds

    # [6] 로그 기록
    write_log "${APP_PID}"
}

main "$@"
