#!/bin/bash
# =============================================================================
# run-scenario.sh - 장애 시나리오 재현 + 증거 수집 오케스트레이터 (b1-2 미션)
#
# agent-leak-app을 지정한 환경변수로 실행하면서, 동시에 monitor.sh로 자원을
# 관제한다. 앱 자체 로그와 monitor.sh 관제 로그를 시나리오별 폴더에 저장하여
# 리포트 증거로 사용한다.
#
# 사용법:
#   run-scenario.sh <label> <MEMORY_LIMIT> <CPU_MAX_OCCUPY> <MULTI_THREAD_ENABLE> [MAX_SECONDS]
#
# 예:
#   run-scenario.sh oom_before   128 50 false 90
#   run-scenario.sh oom_after    512 50 false 90
#   run-scenario.sh cpu_before   512 90 false 90
#   run-scenario.sh cpu_after    512 40 false 60
#   run-scenario.sh deadlock     512 50 true  40
#   run-scenario.sh scheduling   512 10 false 40
# =============================================================================

set -uo pipefail

AGENT_HOME="${AGENT_HOME:-/home/agent/agent-app}"
APP_BIN="${APP_BIN:-$AGENT_HOME/bin/agent-leak-app}"
MONITOR="${MONITOR:-$AGENT_HOME/bin/monitor.sh}"
EVIDENCE_ROOT="${EVIDENCE_ROOT:-$AGENT_HOME/evidence}"

LABEL="${1:?라벨을 지정하세요 (예: oom_before)}"
MEMORY_LIMIT_IN="${2:?MEMORY_LIMIT을 지정하세요}"
CPU_MAX_OCCUPY_IN="${3:?CPU_MAX_OCCUPY를 지정하세요}"
MULTI_THREAD_IN="${4:?MULTI_THREAD_ENABLE를 지정하세요}"
MAX_SECONDS="${5:-90}"

OUT_DIR="$EVIDENCE_ROOT/$LABEL"
APP_LOG="$OUT_DIR/app.log"
MON_LOG="$OUT_DIR/monitor.log"

# 필수 실행 환경변수 (부트 시퀀스 통과 요건)
export AGENT_HOME
export AGENT_PORT="${AGENT_PORT:-15034}"
export AGENT_UPLOAD_DIR="$AGENT_HOME/upload_files"
export AGENT_KEY_PATH="$AGENT_HOME/api_keys"
export AGENT_LOG_DIR="$AGENT_HOME/logs"
export MEMORY_LIMIT="$MEMORY_LIMIT_IN"
export CPU_MAX_OCCUPY="$CPU_MAX_OCCUPY_IN"
export MULTI_THREAD_ENABLE="$MULTI_THREAD_IN"

mkdir -p "$OUT_DIR"
: > "$APP_LOG"
: > "$MON_LOG"
: > "$OUT_DIR/threads_snapshot.txt"   # 이전 실행분이 누적되지 않도록 초기화

echo "=================================================================="
echo "[run-scenario] label=$LABEL"
echo "  MEMORY_LIMIT=$MEMORY_LIMIT  CPU_MAX_OCCUPY=$CPU_MAX_OCCUPY  MULTI_THREAD_ENABLE=$MULTI_THREAD_ENABLE"
echo "  max_seconds=$MAX_SECONDS"
echo "  app_log=$APP_LOG"
echo "  monitor_log=$MON_LOG"
echo "=================================================================="

# 1) 앱 기동 (백그라운드)
"$APP_BIN" > "$APP_LOG" 2>&1 &
APP_PID=$!
echo "[run-scenario] app launched (launcher PID=$APP_PID)"

# 2) monitor.sh 기동 (Deadlock 진단을 위해 스레드 상세 포함, 1초 주기)
#    앱 워커 프로세스가 뜰 때까지 잠깐 대기 후 관제 시작.
INTERVAL="${INTERVAL:-1}" \
DURATION="$MAX_SECONDS" \
THREADS="${THREADS:-1}" \
LOG_FILE="$MON_LOG" \
WAIT_FOR_PROCESS=1 \
    "$MONITOR" > /dev/null 2>&1 &
MON_PID=$!
echo "[run-scenario] monitor.sh launched (PID=$MON_PID)"

# 3) 최대 시간까지 앱 종료를 대기. 데드락처럼 안 죽는 경우 MAX_SECONDS 후 정리.
waited=0
while kill -0 "$APP_PID" 2>/dev/null; do
    sleep 1
    waited=$(( waited + 1 ))
    if [ "$waited" -ge "$MAX_SECONDS" ]; then
        echo "[run-scenario] MAX_SECONDS 도달: 앱이 아직 살아있음 (무응답/정상 지속 추정)."
        echo "[run-scenario] 잔존 프로세스 스냅샷을 남기고 정리합니다."
        # 데드락 증거: 살아있는 상태의 스레드 스냅샷을 별도 저장
        pgrep -f agent-leak-app | while read -r p; do
            {
                echo "----- ps -L (thread view) PID=$p @ $(date '+%H:%M:%S') -----"
                ps -L -o pid,tid,stat,pcpu,pmem,wchan,cmd -p "$p"
            } >> "$OUT_DIR/threads_snapshot.txt" 2>&1
        done
        # 앱 + 자식 워커 정리
        pkill -TERM -f agent-leak-app 2>/dev/null
        sleep 2
        pkill -KILL -f agent-leak-app 2>/dev/null
        break
    fi
done

APP_EXIT="?"
if ! kill -0 "$APP_PID" 2>/dev/null; then
    wait "$APP_PID" 2>/dev/null
    APP_EXIT=$?
fi

# 4) monitor 종료 대기/정리
wait "$MON_PID" 2>/dev/null
kill "$MON_PID" 2>/dev/null

echo "[run-scenario] app exit code: $APP_EXIT (elapsed ${waited}s)"
echo "[run-scenario] 수집 완료: $OUT_DIR"
ls -la "$OUT_DIR"
