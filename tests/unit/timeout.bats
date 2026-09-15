#!/usr/bin/env bats
# N-2 systemic hang protection: no single step may wedge the whole run.
# Requires a `timeout`/`gtimeout` binary (present in CI and on Linux).

load '../test_helper'

setup() {
    common_setup
    if [[ -z "$(timeout_bin)" ]]; then skip "no timeout binary available"; fi
}
teardown() { common_teardown; }

# _fixture_module <name> <hook body...> — the smallest thing the engine accepts:
# a meta.sh that declares nothing to install, plus whichever hooks the test
# needs. Nothing to install means engine_install is pure hook-running, which is
# what these tests are about.
_fixture_module() {
    local name="$1"; shift
    mkdir -p "$ENVUP_HOME/modules/$name"
    printf 'NAME="%s"\nDESCRIPTION="fixture"\n' "$name" > "$ENVUP_HOME/modules/$name/meta.sh"
    printf '%s\n' "$@" > "$ENVUP_HOME/modules/$name/hooks.sh"
}

@test "net_run: a command exceeding its budget is killed (non-zero, fast)" {
    run net_run --timeout 1 "hang" -- sleep 30
    [ "$status" -ne 0 ]
}

@test "run_module_hook: a hanging hook is killed by the watchdog and reported failed" {
    _fixture_module hang 'pre_install() { sleep 30; }'
    ENVUP_MODULE_TIMEOUT=1 run run_module_hook hang install
    [ "$status" -ne 0 ]
    [[ "$output" == *"timed out"* ]]
}

@test "run_module_hook: a normal hook still runs to completion with helpers available" {
    _fixture_module ok 'post_install() { log_info "hi from ok"; }'
    run run_module_hook ok install
    [ "$status" -eq 0 ]
    [[ "$output" == *"hi from ok"* ]]
}

@test "run_module_hook: the watchdog child is \$BASH, not whatever 'bash' is on PATH (A8)" {
    # On macOS the CLI re-execs itself into Homebrew's bash 5 because /bin/bash
    # is 3.2. A bare `bash` in the watchdog would drop the hook back to 3.2,
    # where lib.sh's associative arrays are a syntax error — so the module fails
    # with something unreadable on exactly one platform. The stub here stands in
    # for that wrong interpreter: it must never be the one that runs.
    stub_bin bash <<'EOF'
#!/bin/sh
echo "the PATH bash ran the hook" >&2
exit 0
EOF
    _fixture_module ver 'pre_install() { echo "child-major=${BASH_VERSINFO[0]}"; }'

    run run_module_hook ver install
    [ "$status" -eq 0 ]
    [[ "$output" != *"the PATH bash ran the hook"* ]]
    [[ "$output" == *"child-major=${BASH_VERSINFO[0]}"* ]]
    [ "${BASH_VERSINFO[0]}" -ge 4 ]
}
