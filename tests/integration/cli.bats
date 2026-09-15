#!/usr/bin/env bats
# CLI surface: --version, machine-readable status --json, and ENVUP_LOG_LEVEL.
# Runs the real envup against a throwaway HOME (no install, no network).

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    TEST_HOME="$(mktemp -d "${BATS_TMPDIR:-/tmp}/envup-cli.XXXXXX")"
}
teardown() {
    [[ -n "${TEST_HOME:-}" && -d "$TEST_HOME" ]] && rm -rf "$TEST_HOME"
    return 0
}

@test "envup --version prints the VERSION file" {
    run "$REPO_ROOT/envup" --version
    [ "$status" -eq 0 ]
    [ "$output" = "envup $(cat "$REPO_ROOT/VERSION")" ]
}

@test "envup version subcommand and -V agree" {
    run "$REPO_ROOT/envup" version; [ "$status" -eq 0 ]
    v1="$output"
    run "$REPO_ROOT/envup" -V; [ "$status" -eq 0 ]
    [ "$output" = "$v1" ]
}

@test "status --json emits valid JSON" {
    HOME="$TEST_HOME" run "$REPO_ROOT/envup" status --json
    [ "$status" -eq 0 ]
    echo "$output" | jq -e . >/dev/null
}

@test "status --json reports modules with installed=false on a clean HOME" {
    HOME="$TEST_HOME" run "$REPO_ROOT/envup" status --json
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.modules[] | select(.name=="zsh") | .installed == false' >/dev/null
}

@test "ENVUP_LOG_LEVEL=warn hides the info Platform line in status" {
    HOME="$TEST_HOME" run "$REPO_ROOT/envup" status
    [[ "$output" == *"Platform:"* ]]
    HOME="$TEST_HOME" ENVUP_LOG_LEVEL=warn run "$REPO_ROOT/envup" status
    [[ "$output" != *"Platform:"* ]]
}
