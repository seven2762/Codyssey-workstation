#!/bin/bash
# =============================================================================
# monitor.sh - agent-leak-app 자원 관제 스크립트 (b1-2 미션)
#
# 대상 프로세스(agent-leak-app)의 CPU / 물리 메모리(RSS) / 스레드 수 / 상태(STAT)
# / 대기 지점(WCHAN)을 일정 주기로 샘플링하여 타임스탬프와 함께 로그로 남긴다.
#
# 하나의 스크립트로 세 가지 장애의 객관적 증거를 모두 수집한다.
#   - OOM      : RSS(MB) 컬럼이 시간 경과에 따라 상승하는 패턴
#   - CPU Spike: %CPU 컬럼이 급상승하는 구간
#   - Deadlock : PID는 살아있으나 %CPU/RSS 변화가 정체되고, 스레드가
#                blocked(WCHAN=futex 등) 상태로 멈춰 있는 모습
#
# 사용 예:
#   ./monitor.sh                         # 기본값으로 무한 관제
#   INTERVAL=1 DURATION=90 ./monitor.sh  # 1초 주기로 90초 관측 후 종료
#   THREADS=1 ./monitor.sh               # 매 샘플마다 스레드별 상세까지 기록
#   PROCESS_PATTERN=agent-leak-app ./monitor.sh
# =============================================================================

set -uo pipefail

# ----- 설정 (환경변수로 override 가능) ---------------------------------------
PROCESS_PATTERN="${PROCESS_PATTERN:-agent-leak-app}"  # 관제 대상 프로세스 패턴
INTERVAL="${INTERVAL:-2}"                             # 샘플링 주기(초)
DURATION="${DURATION:-0}"                             # 총 관측 시간(초), 0=무한
LOG_DIR="${LOG_DIR:-${AGENT_LOG_DIR:-$HOME/agent-app/logs}}"
LOG_FILE="${LOG_FILE:-$LOG_DIR/monitor.log}"
THREADS="${THREADS:-0}"                               # 1이면 스레드별 상세 기록
WAIT_FOR_PROCESS="${WAIT_FOR_PROCESS:-1}"             # 시작 시 프로세스 등장까지 대기

# 자원 경고 임계값 (관제 로그에 [WARNING] 표시용, 프로세스는 종료하지 않음)
CPU_WARN="${CPU_WARN:-80}"                            # %CPU 경고 임계
MEM_WARN_MB="${MEM_WARN_MB:-400}"                     # RSS(MB) 경고 임계

MAX_LOG_BYTES=$((10 * 1024 * 1024))                  # 로그 롤오버 기준(10MB)

CLK_TCK="$(getconf CLK_TCK 2>/dev/null || echo 100)" # 커널 clock tick(초당 tick 수)

# 순간 CPU 계산용 이전 샘플 상태(프로세스 누적 CPU tick / 측정 시각[ms])
PREV_PID=""
PREV_TICKS=""
PREV_TS_MS=""
INST_CPU="-"   # instant_cpu()가 채우는 결과 전역 변수

# ----- 유틸 ------------------------------------------------------------------
ts() { date '+%Y-%m-%d %H:%M:%S.%3N'; }

log() { echo "$*" | tee -a "$LOG_FILE"; }

rotate_if_needed() {
    [ -f "$LOG_FILE" ] || return 0
    local size
    size=$(stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)
    if [ "$size" -ge "$MAX_LOG_BYTES" ]; then
        mv "$LOG_FILE" "${LOG_FILE}.$(date +%s)"
    fi
}

find_pid() {
    # 부트로더/자식 프로세스가 함께 잡힐 수 있으므로, 실제 워크로드를 수행하는
    # 자식(메모리를 많이 쓰는 쪽)을 우선 선택한다. 없으면 첫 PID를 사용.
    local pids
    pids=$(pgrep -f "$PROCESS_PATTERN" 2>/dev/null || true)
    [ -z "$pids" ] && return 1
    # RSS가 가장 큰 프로세스를 대표 PID로 선택
    echo "$pids" \
        | xargs -r -n1 -I{} sh -c 'echo "$(ps -o rss= -p {} 2>/dev/null || echo 0) {}"' \
        | sort -rn | awk 'NR==1{print $2}'
}

print_header() {
    log "==================================================================================="
    log "[monitor.sh] START $(ts)"
    log "  pattern='${PROCESS_PATTERN}'  interval=${INTERVAL}s  duration=${DURATION}s(0=inf)"
    log "  warn: CPU>${CPU_WARN}%, RSS>${MEM_WARN_MB}MB   (%CPU=/proc 기반 순간값, 1코어=100%)"
    log "-----------------------------------------------------------------------------------"
    log "$(printf '%-25s | %-6s | %-4s | %-6s | %-8s | %-7s | %-8s' \
        'TIMESTAMP' 'PID' 'STAT' '%CPU' 'RSS(MB)' 'THREADS' 'ELAPSED')"
    log "-----------------------------------------------------------------------------------"
}

# /proc/[pid]/stat에서 프로세스 누적 CPU tick(utime+stime)을 읽는다.
# comm 필드(괄호 안, 공백 포함 가능)를 건너뛰기 위해 마지막 ')' 이후를 파싱한다.
read_cpu_ticks() {
    local pid=$1 statline after
    statline=$(cat "/proc/$pid/stat" 2>/dev/null) || return 1
    [ -z "$statline" ] && return 1
    after=${statline##*) }          # "pid (comm) " 이후 = state부터 시작
    # after의 필드: 1=state ... 12=utime 13=stime
    local -a f
    read -ra f <<< "$after"
    local utime=${f[11]} stime=${f[12]}
    [ -z "$utime" ] && return 1
    echo $(( utime + stime ))
}

# 이전 샘플과의 tick 차이로 순간 CPU%(1코어 기준)를 계산해 전역 INST_CPU에 저장한다.
# 주의: 명령 치환 $(...) 서브셸에서 호출하면 전역 상태가 유지되지 않으므로,
#       반드시 직접 호출한 뒤 $INST_CPU를 읽어야 한다.
# 시각은 float 정밀도 문제를 피하기 위해 epoch 밀리초(정수)로 계산한다.
instant_cpu() {
    local pid=$1 ticks now_ms
    if ! ticks=$(read_cpu_ticks "$pid"); then
        INST_CPU="-"
        return
    fi
    now_ms=$(date +%s%3N)
    if [ "$PREV_PID" = "$pid" ] && [ -n "$PREV_TICKS" ] && [ -n "$PREV_TS_MS" ]; then
        INST_CPU=$(awk -v t1="$PREV_TICKS" -v t2="$ticks" -v m1="$PREV_TS_MS" -v m2="$now_ms" -v hz="$CLK_TCK" \
            'BEGIN{ dtms=m2-m1; if(dtms<=0){printf "0.0"} else {printf "%.1f", 100.0*(t2-t1)*1000.0/(hz*dtms)} }')
    else
        INST_CPU="-"    # PID가 새로 잡힌 첫 샘플은 기준점만 저장
    fi
    PREV_PID=$pid
    PREV_TICKS=$ticks
    PREV_TS_MS=$now_ms
}

# 대상 PID 한 개를 샘플링하여 한 줄 기록. 살아있으면 0, 죽었으면 1 반환.
sample_once() {
    local pid=$1
    local line stat rss nlwp etimes rss_mb pcpu note="" formatted
    line=$(ps -o stat=,rss=,nlwp=,etimes= -p "$pid" 2>/dev/null)
    if [ -z "$line" ]; then
        return 1
    fi
    stat=$(echo "$line"   | awk '{print $1}')
    rss=$(echo "$line"    | awk '{print $2}')
    nlwp=$(echo "$line"   | awk '{print $3}')
    etimes=$(echo "$line" | awk '{print $4}')
    rss_mb=$(( rss / 1024 ))
    # %CPU는 ps의 생애 평균이 아닌 /proc 델타 기반 순간값을 사용한다.
    # instant_cpu는 서브셸이 아닌 현재 셸에서 직접 호출해야 전역 상태가 유지된다.
    instant_cpu "$pid"
    pcpu=$INST_CPU

    # 경고 판단 (정수 비교를 위해 %CPU는 소수점 제거)
    local cpu_int=${pcpu%.*}
    case "$cpu_int" in ''|*[!0-9]*) cpu_int=0 ;; esac
    if [ "$cpu_int" -ge "$CPU_WARN" ]; then
        note="${note}[WARNING CPU>=${CPU_WARN}%] "
    fi
    if [ "$rss_mb" -ge "$MEM_WARN_MB" ]; then
        note="${note}[WARNING RSS>=${MEM_WARN_MB}MB] "
    fi
    # D(uninterruptible sleep) 상태는 I/O 또는 락 대기의 신호일 수 있음
    case "$stat" in
        D*) note="${note}[STATE D: blocked] " ;;
    esac

    printf -v formatted '%-25s | %-6s | %-4s | %-6s | %-8s | %-7s | %-8s %s' \
        "$(ts)" "$pid" "$stat" "$pcpu" "$rss_mb" "$nlwp" "${etimes}s" "$note"
    # 고정폭 컬럼 뒤의 패딩은 가독성에 필요하지만 줄 끝 공백은 증거 diff를
    # 불필요하게 더럽힌다. 마지막 비공백 이후의 suffix만 제거한다.
    formatted=${formatted%"${formatted##*[![:space:]]}"}
    log "$formatted"

    # 스레드별 상세(Deadlock 진단용): TID/상태/CPU/대기지점(WCHAN)
    if [ "$THREADS" = "1" ]; then
        ps -L -o tid=,stat=,pcpu=,wchan= -p "$pid" 2>/dev/null \
            | while read -r tid tstat tcpu twchan; do
                log "        └ thread TID=${tid} STAT=${tstat} CPU=${tcpu}% WCHAN=${twchan}"
            done
    fi
    return 0
}

# ----- 메인 -----------------------------------------------------------------
mkdir -p "$LOG_DIR"
rotate_if_needed
print_header

start_epoch=$(date +%s)

# 프로세스가 아직 안 떴다면 잠시 대기 (관제를 앱보다 먼저 띄우는 경우 대비)
pid=""
if [ "$WAIT_FOR_PROCESS" = "1" ]; then
    for _ in $(seq 1 30); do
        pid=$(find_pid) && [ -n "$pid" ] && break
        sleep 1
    done
fi
[ -z "$pid" ] && pid=$(find_pid || true)

if [ -z "$pid" ]; then
    log "[monitor.sh] 대상 프로세스를 찾지 못했습니다: '${PROCESS_PATTERN}'"
    log "[monitor.sh] 먼저 agent-leak-app을 실행한 뒤 monitor.sh를 실행하세요."
    exit 1
fi

log "[monitor.sh] 관제 시작: PID=${pid}"

missing_count=0
while true; do
    # 종료 시간 도달 여부
    if [ "$DURATION" -gt 0 ]; then
        now=$(date +%s)
        [ $(( now - start_epoch )) -ge "$DURATION" ] && {
            log "[monitor.sh] 지정한 관측 시간(${DURATION}s) 도달. 종료합니다."
            break
        }
    fi

    rotate_if_needed
    if ! sample_once "$pid"; then
        # 현재 PID가 사라졌다면 재탐색(자가 종료/재기동 대비)
        missing_count=$(( missing_count + 1 ))
        newpid=$(find_pid || true)
        if [ -n "$newpid" ] && [ "$newpid" != "$pid" ]; then
            log "[monitor.sh] PID 변경 감지: ${pid} -> ${newpid} (프로세스 재기동 추정)"
            pid=$newpid
            missing_count=0
        else
            log "[monitor.sh] $(ts) PID=${pid} 프로세스 없음 (종료/소멸 추정). 대기 ${missing_count}/3"
            if [ "$missing_count" -ge 3 ]; then
                log "[monitor.sh] 대상 프로세스가 사라졌습니다. 관제를 종료합니다."
                break
            fi
        fi
    fi
    sleep "$INTERVAL"
done

log "[monitor.sh] STOP $(ts)"
