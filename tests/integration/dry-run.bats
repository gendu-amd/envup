#!/usr/bin/env bats
# I4 end-to-end: `install --dry-run` for every profile must exit 0 and create
# no config symlinks in $HOME. Runs against the real repo with a throwaway HOME.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    TEST_HOME="$(mktemp -d "${BATS_TMPDIR:-/tmp}/envup-int.XXXXXX")"
}
teardown() {
    [[ -n "${TEST_HOME:-}" && -d "$TEST_HOME" ]] && rm -rf "$TEST_HOME"
    return 0
}

_no_config_symlinks() {
    # None of the config targets envup would link should exist after a dry-run.
    [ ! -e "$TEST_HOME/.zshrc" ]
    [ ! -e "$TEST_HOME/.gitconfig" ]
    [ ! -e "$TEST_HOME/.tmux.conf" ]
    [ ! -e "$TEST_HOME/.config/nvim" ]
}

@test "install --dry-run: minimal profile is side-effect free" {
    HOME="$TEST_HOME" run "$REPO_ROOT/envup" install -p minimal --dry-run
    [ "$status" -eq 0 ]
    _no_config_symlinks
}

@test "install --dry-run: standard profile is side-effect free" {
    HOME="$TEST_HOME" run "$REPO_ROOT/envup" install -p standard --dry-run
    [ "$status" -eq 0 ]
    _no_config_symlinks
}

@test "install --dry-run: full profile is side-effect free" {
    HOME="$TEST_HOME" run "$REPO_ROOT/envup" install -p full --dry-run
    [ "$status" -eq 0 ]
    _no_config_symlinks
}

@test "install --dry-run: the shell itself reports no errors" {
    # A helper was renamed and one caller was missed. bash reported it on every
    # single run — `pkg_have: command not found`, three times — and every test
    # here still passed, because they assert exit codes and symlinks and nobody
    # was reading stderr. The cost was not cosmetic: the call it broke was the
    # one that decides whether a prerequisite is already installed, so the
    # answer was always "no" and every install ran apt-get for packages the
    # machine already had.
    local p
    for p in minimal standard full; do
        HOME="$TEST_HOME" run "$REPO_ROOT/envup" install -p "$p" --dry-run
        [[ "$output" != *"command not found"* ]] || { echo "$output"; return 1; }
        [[ "$output" != *"unbound variable"* ]]  || { echo "$output"; return 1; }
        [[ "$output" != *"syntax error"* ]]      || { echo "$output"; return 1; }
    done
}

@test "the read-only commands report no shell errors either" {
    # Same guard, for the commands you run when something already looks wrong.
    # `doctor --authoring` and not `doctor`, because the machine health check
    # probes the network and this suite must pass offline.
    local args
    for args in "status" "status --json" "doctor --authoring" "--version"; do
        # shellcheck disable=SC2086
        HOME="$TEST_HOME" run "$REPO_ROOT/envup" $args
        [[ "$output" != *"command not found"* ]] || { echo "$args: $output"; return 1; }
        [[ "$output" != *"unbound variable"* ]]  || { echo "$args: $output"; return 1; }
    done
}

@test "install --dry-run: previews the resolved install order" {
    HOME="$TEST_HOME" run "$REPO_ROOT/envup" install -p standard --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"install order"* ]]
}
