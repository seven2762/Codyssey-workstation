#!/usr/bin/env bash

set -u
set -o pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
FAILURES=0
TMP_ROOT=$(mktemp -d)

cleanup() {
    rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

new_tmp_dir() {
    mktemp -d "$TMP_ROOT/case.XXXXXX"
}

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

assert_dir() {
    local path=$1 description=$2
    if [ -d "$path" ]; then
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

assert_not_contains() {
    local path=$1 pattern=$2 description=$3
    if [ -f "$path" ] && ! grep -Eq "$pattern" "$path"; then
        pass "$description"
    else
        fail "$description (unexpected pattern '$pattern' in $path)"
    fi
}

assert_command_succeeds() {
    local description=$1
    shift
    if "$@" >/dev/null 2>&1; then
        pass "$description"
    else
        fail "$description"
    fi
}

assert_command_fails() {
    local description=$1
    shift
    if "$@" >/dev/null 2>&1; then
        fail "$description (command unexpectedly succeeded)"
    else
        pass "$description"
    fi
}

run_setup_contract_test() {
    local tmp agent_home env_file output rc
    tmp=$(new_tmp_dir)
    agent_home="$tmp/agent-app"
    env_file="$tmp/agent.env"
    output="$tmp/setup.stdout"

    AGENT_HOME="$agent_home" ENV_FILE="$env_file" \
        bash "$ROOT_DIR/setup-agent-env.sh" > "$output" 2>&1
    rc=$?

    if [ "$rc" -eq 0 ]; then
        pass "setup-agent-env.sh configures a temporary agent home"
    else
        fail "setup-agent-env.sh configures a temporary agent home (rc=$rc)"
    fi

    assert_dir "$agent_home/upload_files" "setup creates upload directory"
    assert_dir "$agent_home/api_keys" "setup creates API key directory"
    assert_dir "$agent_home/logs" "setup creates log directory"
    assert_file "$agent_home/api_keys/secret.key" "setup creates the required key file"
    assert_contains "$agent_home/api_keys/secret.key" '^agent_api_key_test$' \
        "setup writes the binary's expected test key"
    assert_contains "$env_file" '^export AGENT_HOME=' "setup writes a sourceable environment file"
    assert_contains "$env_file" '^export AGENT_PORT=15034$' "setup writes the required port"

    printf '%s\n' 'preserve_existing_key' > "$agent_home/api_keys/secret.key"
    AGENT_HOME="$agent_home" ENV_FILE="$env_file" \
        bash "$ROOT_DIR/setup-agent-env.sh" > "$output" 2>&1
    assert_contains "$agent_home/api_keys/secret.key" '^preserve_existing_key$' \
        "setup is idempotent and does not overwrite an existing key"
}

run_runner_contract_test() {
    local tmp app_bin monitor evidence output rc
    tmp=$(new_tmp_dir)
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

    assert_contains "$evidence/cpu_contract/run.log" '^app_exit_code=143$' \
        "runner persists application exit code in run.log"
    assert_contains "$evidence/cpu_contract/run.log" '^MEMORY_LIMIT=512$' \
        "runner persists scenario environment in run.log"
    assert_contains "$evidence/cpu_contract/run.log" '^timed_out=false$' \
        "runner distinguishes natural exit from timeout cleanup"
    assert_contains "$evidence/cpu_contract/app.log" 'fake app started' \
        "runner captures application output"
}

run_all_contract_test() {
    local tmp fake_runner fake_verify calls output rc
    tmp=$(new_tmp_dir)
    fake_runner="$tmp/fake-runner.sh"
    fake_verify="$tmp/fake-verify.sh"
    calls="$tmp/scenario.calls"
    output="$tmp/run-all.stdout"

    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'printf "%s %s %s %s %s\n" "$1" "$2" "$3" "$4" "$5" >> "$CALLS_FILE"' \
        'mkdir -p "$EVIDENCE_ROOT/$1"' > "$fake_runner"
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'printf "verify EVIDENCE_ROOT=%s\n" "$EVIDENCE_ROOT" >> "$CALLS_FILE"' > "$fake_verify"
    chmod 755 "$fake_runner" "$fake_verify"

    CALLS_FILE="$calls" EVIDENCE_ROOT="$tmp/evidence" \
        SCENARIO_RUNNER="$fake_runner" VERIFY_RUNNER="$fake_verify" \
        bash "$ROOT_DIR/run-all-scenarios.sh" > "$output" 2>&1
    rc=$?

    if [ "$rc" -eq 0 ]; then
        pass "run-all-scenarios.sh executes the full workflow"
    else
        fail "run-all-scenarios.sh executes the full workflow (rc=$rc)"
    fi

    assert_contains "$calls" '^oom_before 128 50 false 40$' "run-all includes OOM Before"
    assert_contains "$calls" '^oom_after 512 50 false 75$' "run-all includes OOM After"
    assert_contains "$calls" '^cpu_before 512 90 false 50$' "run-all includes CPU Before"
    assert_contains "$calls" '^cpu_after 512 40 false 45$' "run-all includes CPU After"
    assert_contains "$calls" '^deadlock_before 512 50 true 35$' "run-all includes Deadlock Before"
    assert_contains "$calls" '^deadlock_after 512 50 false 35$' "run-all includes Deadlock After"
    assert_contains "$calls" '^scheduling 512 10 false 35$' "run-all includes scheduling evidence"
    assert_contains "$calls" '^verify EVIDENCE_ROOT=' "run-all verifies evidence after collection"
}

write_base_fixture() {
    local root=$1 label=$2 memory=$3 cpu=$4 multithread=$5 timed_out=$6 exit_code=$7
    local multithread_display
    if [ "$multithread" = "true" ]; then
        multithread_display=True
    else
        multithread_display=False
    fi
    mkdir -p "$root/$label"
    printf '%s\n' \
        'All Boot Checks Passed!' \
        'Agent READY' \
        "... MEMORY_LIMIT=${memory}MB, CPU_MAX_OCCUPY=${cpu}%, MULTI_THREAD_ENABLE=${multithread_display}" \
        > "$root/$label/app.log"
    printf '%s\n' 'monitor sample' > "$root/$label/monitor.log"
    printf '%s\n' \
        "label=$label" \
        "MEMORY_LIMIT=$memory" \
        "CPU_MAX_OCCUPY=$cpu" \
        "MULTI_THREAD_ENABLE=$multithread" \
        "timed_out=$timed_out" \
        "app_exit_code=$exit_code" \
        > "$root/$label/run.log"
    : > "$root/$label/threads_snapshot.txt"
}

run_verifier_contract_test() {
    local tmp evidence output rc
    tmp=$(new_tmp_dir)
    evidence="$tmp/evidence"
    output="$tmp/verify.stdout"

    write_base_fixture "$evidence" oom_before 128 50 false false 137
    write_base_fixture "$evidence" oom_after 512 50 false true 143
    write_base_fixture "$evidence" cpu_before 512 90 false false 143
    write_base_fixture "$evidence" cpu_after 512 40 false true 143
    write_base_fixture "$evidence" deadlock_before 512 50 true true 143
    write_base_fixture "$evidence" deadlock_after 512 50 false true 143
    write_base_fixture "$evidence" scheduling 512 10 false true 143

    printf '%s\n' '[CRITICAL] Memory limit exceeded' >> "$evidence/oom_before/app.log"
    printf '%s\n' '>>> [SYSTEM] MEMORY RECOVERED (Cache Cleared) <<<' >> "$evidence/oom_after/app.log"
    printf '%s\n' '[CRITICAL] CPU Threshold Violated!' >> "$evidence/cpu_before/app.log"
    printf '%s\n' '[CpuWorker] Peak reached (40.00%).' >> "$evidence/cpu_after/app.log"
    printf '%s\n' 'WAITING for [Socket_Pool_B]... (Status: BLOCKED)' >> "$evidence/deadlock_before/app.log"
    printf '%s\n' 'futex_wait' >> "$evidence/deadlock_before/threads_snapshot.txt"
    printf '%s\n' '>>> Scenario Selected: [Healthy System Monitoring]' >> "$evidence/scheduling/app.log"

    EVIDENCE_ROOT="$evidence" bash "$ROOT_DIR/verify-results.sh" > "$output" 2>&1
    rc=$?
    if [ "$rc" -eq 0 ]; then
        pass "verify-results.sh accepts complete valid evidence"
    else
        fail "verify-results.sh accepts complete valid evidence (rc=$rc)"
    fi

    assert_not_contains "$evidence/deadlock_after/app.log" 'Status: BLOCKED' \
        "Deadlock After fixture remains free of blocked workers"

    sed -i.bak '/CPU Threshold Violated/d' "$evidence/cpu_before/app.log"
    assert_command_fails "verify-results.sh rejects missing CPU failure evidence" \
        env EVIDENCE_ROOT="$evidence" bash "$ROOT_DIR/verify-results.sh"
}

run_host_cli_contract_test() {
    local tmp output rc
    tmp=$(new_tmp_dir)
    output="$tmp/help.stdout"

    bash "$ROOT_DIR/orbstack-machine.sh" --help > "$output" 2>&1
    rc=$?
    if [ "$rc" -eq 0 ]; then
        pass "orbstack-machine.sh exposes help without requiring OrbStack"
    else
        fail "orbstack-machine.sh exposes help without requiring OrbStack (rc=$rc)"
    fi

    assert_contains "$output" 'run-all' "host CLI documents full scenario execution"
    assert_contains "$output" 'verify' "host CLI documents VM/evidence verification"
    assert_contains "$output" 'reset-demo' "host CLI documents clean-room demo flow"
    assert_contains "$output" 'collect' "host CLI documents evidence collection"

    assert_command_fails "host CLI rejects option/path-like machine names" \
        env MACHINE_NAME='../unsafe' ORB_BIN=/usr/bin/true \
        bash "$ROOT_DIR/orbstack-machine.sh" list
}

assert_executable "$ROOT_DIR/monitor.sh" "monitor.sh is directly executable"
assert_executable "$ROOT_DIR/run-scenario.sh" "run-scenario.sh is directly executable"
assert_executable "$ROOT_DIR/setup-agent-env.sh" "setup-agent-env.sh is directly executable"
assert_executable "$ROOT_DIR/run-all-scenarios.sh" "run-all-scenarios.sh is directly executable"
assert_executable "$ROOT_DIR/verify-results.sh" "verify-results.sh is directly executable"
assert_executable "$ROOT_DIR/verify-orbstack.sh" "verify-orbstack.sh is directly executable"
assert_executable "$ROOT_DIR/provision-orbstack.sh" "provision-orbstack.sh is directly executable"
assert_executable "$ROOT_DIR/orbstack-machine.sh" "orbstack-machine.sh is directly executable"

run_setup_contract_test
run_runner_contract_test
run_all_contract_test
run_verifier_contract_test
run_host_cli_contract_test

assert_file "$ROOT_DIR/evidence/oom_before/app.log" "OOM Before application evidence exists"
assert_file "$ROOT_DIR/evidence/oom_after/app.log" "OOM After application evidence exists"
assert_contains "$ROOT_DIR/evidence/oom_before/app.log" 'Memory limit exceeded' \
    "OOM Before records the MemoryGuard failure"
assert_contains "$ROOT_DIR/evidence/oom_after/app.log" 'MEMORY RECOVERED' \
    "OOM After records recovery"
assert_contains "$ROOT_DIR/evidence/cpu_before/app.log" 'CPU Threshold Violated' \
    "CPU Before records the watchdog failure"
assert_contains "$ROOT_DIR/evidence/cpu_after/app.log" 'Peak reached \(40\.00%\)' \
    "CPU After remains below the watchdog threshold"
assert_contains "$ROOT_DIR/evidence/deadlock/app.log" 'Status: BLOCKED' \
    "legacy Deadlock evidence records blocked workers"
assert_contains "$ROOT_DIR/evidence/deadlock/threads_snapshot.txt" 'futex' \
    "legacy Deadlock evidence records kernel lock waits"
assert_command_succeeds "checked-in VM evidence passes the full verifier" \
    env EVIDENCE_ROOT="$ROOT_DIR/evidence" bash "$ROOT_DIR/verify-results.sh"

if [ "$FAILURES" -gt 0 ]; then
    printf '\n%d submission check(s) failed.\n' "$FAILURES" >&2
    exit 1
fi

printf '\nAll submission checks passed.\n'
