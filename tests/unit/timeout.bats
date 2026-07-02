#!/usr/bin/env bats
# N-2 systemic hang protection: no single step may wedge the whole run.
# Requires a `timeout`/`gtimeout` binary (present in CI and on Linux).

load '../test_helper'

setup() {
    common_setup
    if [[ -z "$(_net_timeout_bin)" ]]; then skip "no timeout binary available"; fi
}
teardown() { common_teardown; }

@test "net_run: a command exceeding its budget is killed (non-zero, fast)" {
    run net_run --timeout 1 "hang" -- sleep 30
    [ "$status" -ne 0 ]
}

@test "run_module_hook: a hanging hook is killed by the watchdog and reported failed" {
    mkdir -p "$ENVUP_HOME/modules/hang"
    echo 'sleep 30' > "$ENVUP_HOME/modules/hang/install.sh"
    ENVUP_MODULE_TIMEOUT=1 run run_module_hook hang install
    [ "$status" -ne 0 ]
    [[ "$output" == *"timed out"* ]]
}

@test "run_module_hook: a normal hook still runs to completion with helpers available" {
    mkdir -p "$ENVUP_HOME/modules/ok"
    echo 'log_info "hi from ok"' > "$ENVUP_HOME/modules/ok/install.sh"
    run run_module_hook ok install
    [ "$status" -eq 0 ]
    [[ "$output" == *"hi from ok"* ]]
}
