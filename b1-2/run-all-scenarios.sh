#!/usr/bin/env bash

set -euo pipefail

AGENT_HOME="${AGENT_HOME:-/home/agent/agent-app}"
ENV_FILE="${ENV_FILE:-${AGENT_HOME}/.env}"
if [ -r "$ENV_FILE" ]; then
    # shellcheck disable=SC1090
    source "$ENV_FILE"
fi

SCENARIO_RUNNER="${SCENARIO_RUNNER:-${AGENT_HOME}/bin/run-scenario.sh}"
VERIFY_RUNNER="${VERIFY_RUNNER:-${AGENT_HOME}/bin/verify-results.sh}"
EVIDENCE_ROOT="${EVIDENCE_ROOT:-${AGENT_HOME}/evidence}"
VERIFY_AFTER_RUN="${VERIFY_AFTER_RUN:-1}"
export EVIDENCE_ROOT

run_one() {
    local label=$1 memory=$2 cpu=$3 multithread=$4 seconds=$5
    printf '\n==================================================================\n'
    printf '[run-all] %s (memory=%s cpu=%s multithread=%s seconds=%s)\n' \
        "$label" "$memory" "$cpu" "$multithread" "$seconds"
    printf '==================================================================\n'
    "$SCENARIO_RUNNER" "$label" "$memory" "$cpu" "$multithread" "$seconds"
}

main() {
    [ -x "$SCENARIO_RUNNER" ] || {
        printf '[ERROR] scenario runner is not executable: %s\n' "$SCENARIO_RUNNER" >&2
        exit 1
    }

    mkdir -p "$EVIDENCE_ROOT"

    run_one oom_before 128 50 false 40
    run_one oom_after 512 50 false 75
    run_one cpu_before 512 90 false 50
    run_one cpu_after 512 40 false 45
    run_one deadlock_before 512 50 true 35
    run_one deadlock_after 512 50 false 35
    run_one scheduling 512 10 false 35

    if [ "$VERIFY_AFTER_RUN" = "1" ]; then
        printf '\n[run-all] validating collected evidence\n'
        "$VERIFY_RUNNER"
    fi
}

main "$@"
