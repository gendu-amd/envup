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

@test "install --dry-run: previews the resolved install order" {
    HOME="$TEST_HOME" run "$REPO_ROOT/envup" install -p standard --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"install order"* ]]
}
