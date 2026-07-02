#!/usr/bin/env bats
# WI-3.1: profiles compose (full = standard + nvim, standard = minimal + tools)
# and still resolve to the exact same module order as the pre-refactor lists.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    TEST_HOME="$(mktemp -d "${BATS_TMPDIR:-/tmp}/envup-prof.XXXXXX")"
}
teardown() {
    [[ -n "${TEST_HOME:-}" && -d "$TEST_HOME" ]] && rm -rf "$TEST_HOME"
    return 0
}

@test "minimal resolves to: zsh git" {
    HOME="$TEST_HOME" run "$REPO_ROOT/envup" install -p minimal --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"install order: zsh git"* ]]
}

@test "standard resolves to: zsh git tmux fzf zoxide atuin" {
    HOME="$TEST_HOME" run "$REPO_ROOT/envup" install -p standard --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"install order: zsh git tmux fzf zoxide atuin"* ]]
}

@test "full resolves to: zsh git tmux fzf zoxide atuin nvim" {
    HOME="$TEST_HOME" run "$REPO_ROOT/envup" install -p full --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"install order: zsh git tmux fzf zoxide atuin nvim"* ]]
}
