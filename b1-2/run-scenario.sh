#!/usr/bin/env bash

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_HOME="${AGENT_HOME:-/home/agent/agent-app}"
ENV_FILE="${ENV_FILE:-${AGENT_HOME}/.env}"
if [ -r "$ENV_FILE" ]; then
    # shellcheck disable=SC1090
    source "$ENV_FILE"
fi

if [ -x "$AGENT_HOME/bin/agent-leak-app" ]; then
    DEFAULT_APP_BIN="$AGENT_HOME/bin/agent-leak-app"
else
    DEFAULT_APP_BIN="$SCRIPT_DIR/agent-leak-app-x86"
fi

if [ -x "$AGENT_HOME/bin/monitor.sh" ]; then
    DEFAULT_MONITOR="$AGENT_HOME/bin/monitor.sh"
else
    DEFAULT_MONITOR="$SCRIPT_DIR/monitor.sh"
fi

APP_BIN="${APP_BIN:-$DEFAULT_APP_BIN}"
MONITOR="${MONITOR:-$DEFAULT_MONITOR}"
EVIDENCE_ROOT="${EVIDENCE_ROOT:-$AGENT_HOME/evidence}"

LABEL="${1:-}"
MEMORY_LIMIT_IN="${2:-}"
CPU_MAX_OCCUPY_IN="${3:-}"
MULTI_THREAD_IN="${4:-}"
MAX_SECONDS="${5:-90}"

APP_PID=""
MON_PID=""
FINALIZED=0

die() {
    printf '[ERROR] %s\n' "$*" >&2
    exit 1
}

validate_integer_range() {
    local name=$1 value=$2 minimum=$3 maximum=$4
    case "$value" in
        ''|*[!0-9]*) die "$name must be an integer: $value" ;;
    esac
    if [ "$value" -lt "$minimum" ] || [ "$value" -gt "$maximum" ]; then
        die "$name must be between $minimum and $maximum: $value"
    fi
}

validate_inputs() {
    [[ "$LABEL" =~ ^[a-z0-9][a-z0-9_-]*$ ]] \
        || die "label may contain only lowercase letters, digits, '_' and '-': $LABEL"
    validate_integer_range MEMORY_LIMIT "$MEMORY_LIMIT_IN" 50 512
    validate_integer_range CPU_MAX_OCCUPY "$CPU_MAX_OCCUPY_IN" 10 100
    validate_integer_range MAX_SECONDS "$MAX_SECONDS" 1 3600
    case "$MULTI_THREAD_IN" in
        true|false) ;;
        *) die "MULTI_THREAD_ENABLE must be true or false: $MULTI_THREAD_IN" ;;
    esac
    [ -x "$APP_BIN" ] || die "application binary is not executable: $APP_BIN"
    [ -x "$MONITOR" ] || die "monitor script is not executable: $MONITOR"
}

tree_pids() {
    local pid=$1 child
    [ -n "$pid" ] || return 0
    for child in $(pgrep -P "$pid" 2>/dev/null || true); do
        tree_pids "$child"
    done
    printf '%s\n' "$pid"
}

terminate_tree() {
    local root_pid=$1 pids pid
    pids=$(tree_pids "$root_pid")
    for pid in $pids; do
        kill -TERM "$pid" 2>/dev/null || true
    done
    sleep 2
    # 부모가 TERM으로 먼저 종료되어 자식이 고아가 되어도, TERM 전에 저장한 PID
    # 목록으로 KILL까지 보장한다. 다른 agent-leak-app 실행은 건드리지 않는다.
    for pid in $pids; do
        kill -KILL "$pid" 2>/dev/null || true
    done
}

cleanup() {
    [ "$FINALIZED" -eq 1 ] && return
    if [ -n "$MON_PID" ] && kill -0 "$MON_PID" 2>/dev/null; then
        kill "$MON_PID" 2>/dev/null || true
    fi
    if [ -n "$APP_PID" ] && kill -0 "$APP_PID" 2>/dev/null; then
        terminate_tree "$APP_PID"
    fi
}
trap cleanup EXIT INT TERM

snapshot_tree() {
    local root_pid=$1 output_file=$2 pid
    {
        printf '%s\n' "----- process tree @ $(date '+%Y-%m-%d %H:%M:%S') -----"
        for pid in $(tree_pids "$root_pid"); do
            ps -L -o pid,ppid,tid,stat,pcpu,pmem,wchan,cmd -p "$pid" 2>/dev/null || true
        done
    } >> "$output_file"
}

write_run_value() {
    printf '%s=%s\n' "$1" "$2" | tee -a "$RUN_LOG"
}

normalize_log() {
    local path=$1 temp
    [ -f "$path" ] || return 0
    temp=$(mktemp "${path}.tmp.XXXXXX") || return 1
    if sed 's/[[:space:]]*$//' "$path" > "$temp"; then
        mv "$temp" "$path"
    else
        rm -f "$temp"
        return 1
    fi
}

main() {
    local waited=0 timed_out=false app_exit monitor_exit
    validate_inputs

    OUT_DIR="$EVIDENCE_ROOT/$LABEL"
    APP_LOG="$OUT_DIR/app.log"
    MON_LOG="$OUT_DIR/monitor.log"
    THREADS_LOG="$OUT_DIR/threads_snapshot.txt"
    RUN_LOG="$OUT_DIR/run.log"

    export AGENT_HOME
    export AGENT_PORT="${AGENT_PORT:-15034}"
    export AGENT_UPLOAD_DIR="${AGENT_UPLOAD_DIR:-$AGENT_HOME/upload_files}"
    export AGENT_KEY_PATH="${AGENT_KEY_PATH:-$AGENT_HOME/api_keys}"
    export AGENT_LOG_DIR="${AGENT_LOG_DIR:-$AGENT_HOME/logs}"
    export MEMORY_LIMIT="$MEMORY_LIMIT_IN"
    export CPU_MAX_OCCUPY="$CPU_MAX_OCCUPY_IN"
    export MULTI_THREAD_ENABLE="$MULTI_THREAD_IN"

    mkdir -p "$OUT_DIR" "$AGENT_UPLOAD_DIR" "$AGENT_KEY_PATH" "$AGENT_LOG_DIR"
    : > "$APP_LOG"
    : > "$MON_LOG"
    : > "$THREADS_LOG"
    : > "$RUN_LOG"

    write_run_value label "$LABEL"
    write_run_value started_at "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    write_run_value MEMORY_LIMIT "$MEMORY_LIMIT"
    write_run_value CPU_MAX_OCCUPY "$CPU_MAX_OCCUPY"
    write_run_value MULTI_THREAD_ENABLE "$MULTI_THREAD_ENABLE"
    write_run_value max_seconds "$MAX_SECONDS"

    "$APP_BIN" > "$APP_LOG" 2>&1 &
    APP_PID=$!
    write_run_value launcher_pid "$APP_PID"

    PROCESS_PATTERN="${PROCESS_PATTERN:-$(basename "$APP_BIN")}" \
    INTERVAL="${INTERVAL:-1}" \
    DURATION="$MAX_SECONDS" \
    THREADS="${THREADS:-1}" \
    LOG_FILE="$MON_LOG" \
    WAIT_FOR_PROCESS=1 \
        "$MONITOR" > /dev/null 2>&1 &
    MON_PID=$!
    write_run_value monitor_pid "$MON_PID"

    while kill -0 "$APP_PID" 2>/dev/null; do
        sleep 1
        waited=$((waited + 1))
        if [ "$waited" -ge "$MAX_SECONDS" ]; then
            timed_out=true
            snapshot_tree "$APP_PID" "$THREADS_LOG"
            terminate_tree "$APP_PID"
            break
        fi
    done

    if wait "$APP_PID" 2>/dev/null; then
        app_exit=0
    else
        app_exit=$?
    fi
    APP_PID=""

    if wait "$MON_PID" 2>/dev/null; then
        monitor_exit=0
    else
        monitor_exit=$?
    fi
    MON_PID=""

    normalize_log "$APP_LOG"
    normalize_log "$MON_LOG"

    write_run_value timed_out "$timed_out"
    write_run_value app_exit_code "$app_exit"
    write_run_value monitor_exit_code "$monitor_exit"
    write_run_value elapsed_seconds "$waited"
    write_run_value completed_at "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

    FINALIZED=1
    trap - EXIT INT TERM

    printf '[run-scenario] collected: %s\n' "$OUT_DIR"
    if [ "$monitor_exit" -ne 0 ]; then
        printf '[ERROR] monitor exited with code %s\n' "$monitor_exit" >&2
        exit 1
    fi
}

main "$@"
