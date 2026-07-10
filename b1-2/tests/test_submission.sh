#!/usr/bin/env bash

set -u
set -o pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
FAILURES=0

pass() {
    printf 'PASS: %s\n' "$1"
}

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    FAILURES=$((FAILURES + 1))
}

assert_file() {
    local path=$1 description=$2
    if [ -f "$path" ]; then
        pass "$description"
    else
        fail "$description (missing: $path)"
    fi
}

assert_executable() {
    local path=$1 description=$2
    if [ -x "$path" ]; then
        pass "$description"
    else
        fail "$description (not executable: $path)"
    fi
}

assert_contains() {
    local path=$1 pattern=$2 description=$3
    if [ -f "$path" ] && grep -Eq "$pattern" "$path"; then
        pass "$description"
    else
        fail "$description (pattern '$pattern' not found in $path)"
    fi
}

assert_cpu_evidence() {
    local before=$1 after=$2
    local before_max after_max

    before_max=$(awk -F'|' '
        /^20[0-9][0-9]-/ {
            gsub(/[[:space:]]/, "", $4)
            if ($4 != "-" && $4 + 0 > max) max = $4 + 0
        }
        END { printf "%.1f", max + 0 }
    ' "$before")
    after_max=$(awk -F'|' '
        /^20[0-9][0-9]-/ {
            gsub(/[[:space:]]/, "", $4)
            if ($4 != "-" && $4 + 0 > max) max = $4 + 0
        }
        END { printf "%.1f", max + 0 }
    ' "$after")

    if awk -v before="$before_max" -v after="$after_max" \
        'BEGIN { exit !(before >= 20.0 && before >= after + 10.0) }'; then
        pass "CPU Before 관제에 실제 프로세스 급상승과 After 개선이 기록됨 (${before_max}% -> ${after_max}%)"
    else
        fail "CPU 실측 증거 부족: Before=${before_max}%, After=${after_max}% (필요: Before>=20%, 차이>=10%p)"
    fi
}

run_runner_contract_test() {
    local tmp app_bin monitor evidence output rc
    tmp=$(mktemp -d)
    app_bin="$tmp/agent-leak-app"
    monitor="$tmp/monitor.sh"
    evidence="$tmp/evidence"

    mkdir -p "$tmp/upload_files" "$tmp/api_keys" "$tmp/logs" "$evidence"
    printf '%s\n' 'agent_api_key_test' > "$tmp/api_keys/secret.key"

    printf '%s\n' '#!/usr/bin/env bash' 'echo "fake app started"' 'exit 143' > "$app_bin"
    printf '%s\n' '#!/usr/bin/env bash' 'printf "fake monitor\n" >> "$LOG_FILE"' > "$monitor"
    chmod 755 "$app_bin" "$monitor"

    output="$tmp/runner.stdout"
    APP_BIN="$app_bin" MONITOR="$monitor" AGENT_HOME="$tmp" EVIDENCE_ROOT="$evidence" \
        bash "$ROOT_DIR/run-scenario.sh" cpu_contract 512 90 false 2 > "$output" 2>&1
    rc=$?

    if [ "$rc" -eq 0 ]; then
        pass "run-scenario.sh contract fixture completes"
    else
        fail "run-scenario.sh contract fixture exits successfully (rc=$rc)"
    fi

    assert_contains "$evidence/cpu_contract/run.log" 'app_exit_code=143' \
        "runner persists application exit code in run.log"
    assert_contains "$evidence/cpu_contract/run.log" 'MEMORY_LIMIT=512' \
        "runner persists scenario environment in run.log"

    rm -rf "$tmp"
}

assert_executable "$ROOT_DIR/monitor.sh" "monitor.sh is directly executable"
assert_executable "$ROOT_DIR/run-scenario.sh" "run-scenario.sh is directly executable"
assert_file "$ROOT_DIR/setup-agent-env.sh" "repository includes a reproducible environment setup script"

run_runner_contract_test

assert_file "$ROOT_DIR/evidence/oom_before/run.log" "OOM Before has runner/exit-code evidence"
assert_file "$ROOT_DIR/evidence/oom_after/run.log" "OOM After has runner/exit-code evidence"
assert_file "$ROOT_DIR/evidence/cpu_before/run.log" "CPU Before has runner/exit-code evidence"
assert_file "$ROOT_DIR/evidence/cpu_after/run.log" "CPU After has runner/exit-code evidence"
assert_file "$ROOT_DIR/evidence/deadlock_after/app.log" "Deadlock After app evidence exists"
assert_file "$ROOT_DIR/evidence/deadlock_after/monitor.log" "Deadlock After monitor evidence exists"
assert_contains "$ROOT_DIR/evidence/deadlock_after/app.log" 'MULTI_THREAD_ENABLE=False' \
    "Deadlock After proves concurrency was disabled"

assert_cpu_evidence \
    "$ROOT_DIR/evidence/cpu_before/monitor.log" \
    "$ROOT_DIR/evidence/cpu_after/monitor.log"

if [ "$FAILURES" -gt 0 ]; then
    printf '\n%d submission check(s) failed.\n' "$FAILURES" >&2
    exit 1
fi

printf '\nAll submission checks passed.\n'
