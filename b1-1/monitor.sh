#!/bin/bash
# =============================================================================
# monitor.sh - Agent App 시스템 상태 수집 및 로깅 스크립트
# 소유자: agent-dev / 그룹: agent-core / 권한: 750
# cron 실행 계정: agent-admin
# =============================================================================

# ── 환경 변수 로드 (단일 소스: systemd와 동일한 .env) ─────────────────────
# systemd agent-app 서비스가 EnvironmentFile로 쓰는 파일을 monitor도 그대로
# 읽어, 앱과 모니터가 항상 같은 AGENT_PORT/경로 설정을 보게 한다.
# cron/대화형 셸은 이 파일을 자동 로드하지 않으므로 여기서 명시적으로 읽는다.
# 파일은 root:agent-core 640 으로 root만 수정 가능 → source 해도 안전하다.
# 아래 ${VAR:-기본값} 은 .env 가 없을 때를 위한 최종 폴백이다.
AGENT_ENV_FILE="${AGENT_ENV_FILE:-/etc/agent-app/agent-app.env}"
if [ -r "${AGENT_ENV_FILE}" ]; then
    set -a
    . "${AGENT_ENV_FILE}"
    set +a
fi

# ── 환경 변수 기본값 설정 (.env 미로드 시 폴백) ────────────────────────────
AGENT_HOME="${AGENT_HOME:-/home/agent-admin/agent-app}"
AGENT_PORT="${AGENT_PORT:-15034}"
AGENT_LOG_DIR="${AGENT_LOG_DIR:-/var/log/agent-app}"
LOG_FILE="${AGENT_LOG_DIR}/monitor.log"
# cron이 monitor.sh의 stdout을 append하는 파일. monitor.log와 마찬가지로
# 매분 커지므로 동일 정책으로 로테이션한다(방치 시 무한 증가).
CRON_LOG_FILE="${AGENT_LOG_DIR}/cron.log"
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
        if ! mkdir -p "${AGENT_LOG_DIR}" 2>/dev/null; then
            echo "[${TIMESTAMP}] [ERROR] 로그 디렉토리 생성 실패: ${AGENT_LOG_DIR}" >&2
            exit 1
        fi
    fi
}

# ── 로그 파일 용량 관리 (최대 10MB / 10개 파일 유지) ─────────────────────
# 인자로 받은 로그 파일이 임계 용량을 넘으면 .1~.N 으로 순환시킨다.
# monitor.log 와 cron.log 에 동일 정책으로 재사용한다.
rotate_log() {
    local log_file="$1"

    if [ ! -f "${log_file}" ]; then
        return
    fi

    local file_size_bytes
    file_size_bytes=$(stat -c%s "${log_file}" 2>/dev/null || echo 0)
    local max_bytes=$(( MAX_LOG_SIZE_MB * 1024 * 1024 ))

    if [ "${file_size_bytes}" -ge "${max_bytes}" ]; then
        # 최대 개수 초과 파일 삭제 (실패 시 조용히 넘기지 않고 경고)
        local oldest="${log_file}.${MAX_LOG_FILES}"
        if [ -f "${oldest}" ]; then
            rm -f "${oldest}" || echo "[${TIMESTAMP}] [WARNING] 오래된 로그 삭제 실패: ${oldest}"
        fi

        # 기존 로테이션 파일들을 한 단계씩 밀기
        for i in $(seq $(( MAX_LOG_FILES - 1 )) -1 1); do
            local src="${log_file}.${i}"
            local dst="${log_file}.$(( i + 1 ))"
            if [ -f "${src}" ]; then
                mv "${src}" "${dst}" || echo "[${TIMESTAMP}] [WARNING] 로그 로테이션 실패: ${src} -> ${dst}"
            fi
        done

        # 현재 로그를 .1로 이동
        mv "${log_file}" "${log_file}.1" || echo "[${TIMESTAMP}] [WARNING] 현재 로그 로테이션 실패: ${log_file}"
    fi
}

# =============================================================================
# [1] Health Check - 프로세스 확인 (실패 시 exit 1)
# =============================================================================
check_process() {
    # 프로세스명(comm)을 정확히 일치(-x)시켜 확인한다.
    # 주의: pgrep -f 는 명령줄 전체를 매칭하므로, 이 스크립트 경로
    # (${AGENT_HOME}/bin/monitor.sh, 예: /home/agent-admin/agent-app/...) 안의
    # "agent-app" 문자열 때문에 monitor.sh 자신/cron 프로세스까지 오탐하여
    # 앱이 죽어도 헬스체크가 통과하는 버그가 있었다. -x 로 프로세스명만 매칭한다.
    #
    # 결과 PID는 전역 변수 APP_PID로 노출한다. exit 1이 스크립트 전체를
    # 종료할 수 있도록, 이 함수는 명령 치환($(...)) 안에서 호출하면 안 된다.
    # 서브셸 안에서 exit 하면 본체가 종료되지 않고 이어서 실행되기 때문이다.
    APP_PID=$(pgrep -x "${APP_PROCESS}" | head -1)

    if [ -z "${APP_PID}" ]; then
        # 사람이 읽는 메시지는 stdout으로만 출력한다(= cron이 cron.log로 수집).
        # monitor.log에는 데이터 라인만 남겨 스펙 포맷을 유지한다.
        echo "[${TIMESTAMP}] [ERROR] 프로세스 '${APP_PROCESS}' 가 실행 중이지 않습니다. 모니터링을 종료합니다."
        exit 1
    fi
}

# =============================================================================
# [2] Health Check - 포트 LISTEN 확인 (실패 시 exit 1)
# =============================================================================
check_port() {
    local listen_check
    listen_check=$(ss -tuln 2>/dev/null | grep "LISTEN" | grep -E ":${AGENT_PORT}\b")

    if [ -z "${listen_check}" ]; then
        echo "[${TIMESTAMP}] [ERROR] TCP ${AGENT_PORT} 포트가 LISTEN 상태가 아닙니다. 모니터링을 종료합니다."
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
            echo "[${TIMESTAMP}] [WARNING] UFW 방화벽이 비활성 상태입니다."
        fi
        return
    fi

    # firewalld 확인
    if command -v firewall-cmd &>/dev/null; then
        fw_status=$(firewall-cmd --state 2>/dev/null)
        if [ "${fw_status}" != "running" ]; then
            echo "[${TIMESTAMP}] [WARNING] firewalld 방화벽이 비활성 상태입니다."
        fi
        return
    fi

    # 방화벽 미설치
    echo "[${TIMESTAMP}] [WARNING] 방화벽(UFW/firewalld)이 설치되어 있지 않습니다."
}

read_cpu_ticks() {
    # /proc/stat cpu 라인 필드:
    #   $2 user  $3 nice  $4 system  $5 idle  $6 iowait
    #   $7 irq   $8 softirq  $9 steal  $10 guest  $11 guest_nice
    # 주의: user($2)에는 guest($10)가, nice($3)에는 guest_nice($11)가 이미
    # 포함돼 있다. total에 $10/$11까지 더하면 guest 시간이 이중 계산되어
    # 사용률이 실제보다 낮게 나온다. total은 $2..$9(user~steal)만 합산한다.
    # idle 시간은 idle + iowait 로 본다.
    awk '
        /^cpu / {
            idle = $5 + $6
            total = 0
            for (i = 2; i <= 9; i++) total += $i
            printf "%d %d\n", idle, total
            exit
        }
    ' /proc/stat
}

# 값을 0~100 범위로 클램프해 소수 1자리로 출력하는 공통 헬퍼
clamp_percent() {
    awk -v v="$1" 'BEGIN {
        if (v < 0) v = 0
        if (v > 100) v = 100
        printf "%.1f", v
    }'
}

# CPU 사용률(%) - /proc/stat 두 샘플 간 tick 증가량으로 계산.
# 성공 시 "%.1f" 출력, 실패 시 아무것도 출력하지 않는다(빈 문자열 → 폴백 유도).
cpu_usage_from_proc_stat() {
    local idle1 total1 idle2 total2
    read -r idle1 total1 < <(read_cpu_ticks) || return 1
    sleep 0.5
    read -r idle2 total2 < <(read_cpu_ticks) || return 1

    local diff_idle=$(( idle2 - idle1 ))
    local diff_total=$(( total2 - total1 ))
    [ "${diff_total}" -gt 0 ] || return 1

    clamp_percent "$(awk -v i="${diff_idle}" -v t="${diff_total}" 'BEGIN{printf "%.4f", (1 - i / t) * 100}')"
}

# CPU 사용률(%) - /proc/stat을 못 읽을 때 top의 idle 값으로 폴백.
cpu_usage_from_top() {
    local idle
    idle=$(top -bn1 2>/dev/null | awk -F',' '/^%?Cpu/ {for (i=1; i<=NF; i++) if ($i ~ / id/) {gsub(/[^0-9.]/, "", $i); print $i; exit}}')
    [ -n "${idle}" ] || return 1
    clamp_percent "$(awk -v idle="${idle}" 'BEGIN{printf "%.4f", 100 - idle}')"
}

# =============================================================================
# [4] 자원 수집 - CPU / MEM / DISK (지표별 개별 함수 + 오케스트레이터)
# =============================================================================
collect_cpu() {
    CPU_USED="$(cpu_usage_from_proc_stat)"
    [ -n "${CPU_USED}" ] || CPU_USED="$(cpu_usage_from_top)"
    CPU_USED="${CPU_USED:-0.0}"
}

collect_mem() {
    # MEM 사용률(%) = (1 - MemAvailable/MemTotal) * 100
    local mem_total mem_available
    mem_total=$(awk '/^MemTotal:/{print $2}' /proc/meminfo)
    mem_available=$(awk '/^MemAvailable:/{print $2}' /proc/meminfo)
    if [ -n "${mem_total}" ] && [ "${mem_total}" -gt 0 ]; then
        MEM_USED=$(clamp_percent "$(awk -v a="${mem_available}" -v t="${mem_total}" 'BEGIN{printf "%.4f", (1 - a / t) * 100}')")
    else
        MEM_USED="0.0"
    fi
}

collect_disk() {
    # 루트 파티션 사용률 (Used %)
    DISK_USED=$(df / 2>/dev/null | tail -1 | awk '{gsub(/%/,"",$5); print $5}')
    DISK_USED="${DISK_USED:-0}"
}

collect_resources() {
    collect_cpu
    collect_mem
    collect_disk
}

# =============================================================================
# [5] 임계값 경고 출력 (종료하지 않음)
# =============================================================================
check_thresholds() {
    # 값은 printf "%.1f" / df 로 생성돼 항상 숫자다. 정수부만 파라미터 확장으로
    # 안전하게 취하고(빈 값이면 0), 예전처럼 "[ ] 2>/dev/null" 로 비교 에러를
    # 숨기지 않는다. 숨기면 값이 깨졌을 때 경고가 조용히 안 울리기 때문이다.
    local cpu_int="${CPU_USED%%.*}";   cpu_int="${cpu_int:-0}"
    local mem_int="${MEM_USED%%.*}";   mem_int="${mem_int:-0}"
    local disk_int="${DISK_USED%%.*}"; disk_int="${disk_int:-0}"

    if [ "${cpu_int}" -gt 20 ]; then
        echo "[${TIMESTAMP}] [WARNING] CPU 사용률 ${CPU_USED}% > 임계값 20%"
    fi

    if [ "${mem_int}" -gt 10 ]; then
        echo "[${TIMESTAMP}] [WARNING] MEM 사용률 ${MEM_USED}% > 임계값 10%"
    fi

    if [ "${disk_int}" -gt 80 ]; then
        echo "[${TIMESTAMP}] [WARNING] DISK 사용률 ${DISK_USED}% > 임계값 80%"
    fi
}

# =============================================================================
# [6] 로그 기록
# 포맷: [YYYY-MM-DD HH:MM:SS] PID:... CPU:..% MEM:..% DISK_USED:..%
# =============================================================================
write_log() {
    local pid="${1}"
    # 데이터 라인은 monitor.log에만 기록한다(스펙 포맷). stdout으로는 내보내지
    # 않아, cron이 stdout을 cron.log로 수집해도 데이터가 중복되지 않는다.
    echo "[${TIMESTAMP}] PID:${pid} CPU:${CPU_USED}% MEM:${MEM_USED}% DISK_USED:${DISK_USED}%" >> "${LOG_FILE}"
    # 기록 완료는 사람이 읽는 확인 메시지로 stdout에만 남긴다.
    echo "[${TIMESTAMP}] [INFO] Log appended: ${LOG_FILE}"
}

# =============================================================================
# MAIN
# =============================================================================
main() {
    # 로그 디렉토리 확인 및 생성
    check_log_dir

    # 로그 로테이션 (용량 초과 시) - monitor.log 와 cron.log 모두 관리
    rotate_log "${LOG_FILE}"
    rotate_log "${CRON_LOG_FILE}"

    # [1] 프로세스 Health Check (APP_PID 전역 설정, 실패 시 스크립트 종료)
    check_process

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
