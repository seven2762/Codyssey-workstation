#!/usr/bin/env bash

set -uo pipefail

AGENT_HOME="${AGENT_HOME:-/home/agent/agent-app}"
EVIDENCE_ROOT="${EVIDENCE_ROOT:-${AGENT_HOME}/evidence}"
FAILURES=0

pass() {
    printf '[PASS] %s\n' "$1"
}

fail() {
    printf '[FAIL] %s\n' "$1" >&2
    FAILURES=$((FAILURES + 1))
}

require_file() {
    local path=$1 description=$2
    if [ -s "$path" ]; then
        pass "$description"
    else
        fail "$description (missing or empty: $path)"
    fi
}

require_contains() {
    local path=$1 pattern=$2 description=$3
    if [ -f "$path" ] && grep -Eq "$pattern" "$path"; then
        pass "$description"
    else
        fail "$description (pattern '$pattern' not found in $path)"
    fi
}

require_not_contains() {
    local path=$1 pattern=$2 description=$3
    if [ -f "$path" ] && ! grep -Eq "$pattern" "$path"; then
        pass "$description"
    else
        fail "$description (unexpected pattern '$pattern' in $path)"
    fi
}

check_common_files() {
    local label=$1
    local dir="$EVIDENCE_ROOT/$label"

    require_file "$dir/app.log" "$label application log"
    require_file "$dir/monitor.log" "$label monitor log"
    require_file "$dir/run.log" "$label runner metadata"
    require_contains "$dir/app.log" 'All Boot Checks Passed!' "$label boot checks"
    require_contains "$dir/app.log" 'Agent READY' "$label ready state"
}

check_environment() {
    local label=$1 memory=$2 cpu=$3 multithread=$4
    local dir="$EVIDENCE_ROOT/$label"

    require_contains "$dir/run.log" "^MEMORY_LIMIT=${memory}$" "$label memory configuration"
    require_contains "$dir/run.log" "^CPU_MAX_OCCUPY=${cpu}$" "$label CPU configuration"
    require_contains "$dir/run.log" "^MULTI_THREAD_ENABLE=${multithread}$" \
        "$label concurrency configuration"
}

main() {
    local label
    for label in \
        oom_before oom_after cpu_before cpu_after \
        deadlock_before deadlock_after scheduling; do
        check_common_files "$label"
    done

    check_environment oom_before 128 50 false
    check_environment oom_after 512 50 false
    check_environment cpu_before 512 90 false
    check_environment cpu_after 512 40 false
    check_environment deadlock_before 512 50 true
    check_environment deadlock_after 512 50 false
    check_environment scheduling 512 10 false

    require_contains "$EVIDENCE_ROOT/oom_before/app.log" 'Memory limit exceeded' \
        "OOM Before reproduces MemoryGuard termination"
    require_contains "$EVIDENCE_ROOT/oom_before/run.log" '^app_exit_code=137$' \
        "OOM Before exits by SIGKILL"
    require_contains "$EVIDENCE_ROOT/oom_after/app.log" 'MEMORY RECOVERED' \
        "OOM After recovers by flushing memory"
    require_contains "$EVIDENCE_ROOT/oom_after/run.log" '^timed_out=true$' \
        "OOM After remains alive for the observation window"

    require_contains "$EVIDENCE_ROOT/cpu_before/app.log" 'CPU Threshold Violated' \
        "CPU Before reproduces watchdog termination"
    require_contains "$EVIDENCE_ROOT/cpu_before/run.log" '^app_exit_code=143$' \
        "CPU Before exits by SIGTERM"
    require_contains "$EVIDENCE_ROOT/cpu_after/app.log" 'Peak reached \(40\.00%\)' \
        "CPU After remains below the watchdog threshold"
    require_contains "$EVIDENCE_ROOT/cpu_after/run.log" '^timed_out=true$' \
        "CPU After remains alive for the observation window"

    require_contains "$EVIDENCE_ROOT/deadlock_before/app.log" 'Status: BLOCKED' \
        "Deadlock Before records blocked workers"
    require_contains "$EVIDENCE_ROOT/deadlock_before/threads_snapshot.txt" 'futex' \
        "Deadlock Before records kernel lock waits"
    require_contains "$EVIDENCE_ROOT/deadlock_before/run.log" '^timed_out=true$' \
        "Deadlock Before remains hung for the observation window"
    require_contains "$EVIDENCE_ROOT/deadlock_after/app.log" 'MULTI_THREAD_ENABLE=False' \
        "Deadlock After disables concurrent workers"
    require_not_contains "$EVIDENCE_ROOT/deadlock_after/app.log" 'Status: BLOCKED' \
        "Deadlock After has no blocked worker evidence"

    require_contains "$EVIDENCE_ROOT/scheduling/app.log" 'Scenario Selected: \[Healthy System Monitoring\]' \
        "healthy settings select the scheduling scenario"

    printf '\n'
    if [ "$FAILURES" -eq 0 ]; then
        printf 'All b1-2 evidence checks passed.\n'
        exit 0
    fi

    printf '%s b1-2 evidence check(s) failed.\n' "$FAILURES" >&2
    exit 1
}

main "$@"
