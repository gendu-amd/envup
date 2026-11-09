#!/usr/bin/env bats
# CLI surface: --version, machine-readable status --json, and ENVUP_LOG_LEVEL.
# Runs the real envup against a throwaway HOME; upgrades use a local upstream.

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

@test "documented Git lifecycle preserves two users' private settings through a source upgrade" {
    export HOME="$TEST_HOME" ENVUP_PRIV=none ENVUP_NET=direct
    export GIT_CONFIG_NOSYSTEM=1
    export ENVUP_STATE_DIR="$HOME/.local/state/envup" ENVUP_LOG_DIR="$HOME/.local/state/envup/logs"
    export ENVUP_LOCAL_BIN="$HOME/.local/bin" ENVUP_LOCAL_OPT="$HOME/.local/opt"
    export ENVUP_BACKUP_DIR="$HOME/backups"
    local upstream="$TEST_HOME/upstream" checkout="$TEST_HOME/checkout" second="$TEST_HOME/second"
    git clone --quiet --no-hardlinks "$REPO_ROOT" "$upstream"
    git clone --quiet --no-hardlinks "$upstream" "$checkout"
    printf '[user]\n name = Original User\n email = original@example.com\n' > "$HOME/.gitconfig"

    run "$checkout/envup" install git --dry-run
    [ "$status" -eq 0 ]
    [ ! -L "$HOME/.gitconfig" ]
    [ ! -e "$ENVUP_STATE_DIR/installed" ]
    run "$checkout/envup" install git
    [ "$status" -eq 0 ]
    [ -L "$HOME/.gitconfig" ]
    [ "$(git config --file "$HOME/.gitconfig.local" user.name)" = "Original User" ]
    [ "$(git config --file "$ENVUP_BACKUP_DIR/.gitconfig" user.name)" = "Original User" ]
    git config --file "$HOME/.gitconfig.local" user.name "First User"
    git config --file "$HOME/.gitconfig.local" alias.st "status --short"
    cp "$HOME/.gitconfig.local" "$TEST_HOME/private-before"
    run "$checkout/envup" install git
    [ "$status" -eq 0 ]
    cmp "$HOME/.gitconfig.local" "$TEST_HOME/private-before"

    mkdir -p "$second"
    HOME="$second" ENVUP_STATE_DIR="$second/state" ENVUP_LOG_DIR="$second/logs" \
        ENVUP_BACKUP_DIR="$second/backups" ENVUP_LOCAL_BIN="$second/bin" \
        ENVUP_LOCAL_OPT="$second/opt" "$checkout/envup" install git
    git config --file "$second/.gitconfig.local" user.name "Second User"
    [ "$(HOME="$second" git config --global --includes user.name)" = "Second User" ]
    [ "$(git config --global --includes user.name)" = "First User" ]
    run "$checkout/envup" doctor --module git
    [ "$status" -eq 0 ]
    run "$checkout/envup" status --json
    [ "$status" -eq 0 ]
    printf '%s\n' "$output" | jq -e '.modules[] | select(.name == "git") | .installed and .state == "ok"' >/dev/null

    git config --file "$upstream/modules/git/files/.gitconfig" alias.envup-lifecycle status
    git config --file "$upstream/modules/git/files/.gitconfig" alias.st status
    git -C "$upstream" add modules/git/files/.gitconfig
    git -C "$upstream" -c user.name="Fixture" -c user.email="fixture@example.com" commit --quiet -m "Update shared Git defaults"
    run "$checkout/envup" upgrade --tools reuse --dry-run
    [ "$status" -eq 0 ]
    [ "$(git -C "$checkout" rev-parse HEAD)" != "$(git -C "$upstream" rev-parse HEAD)" ]
    run "$checkout/envup" upgrade --tools reuse
    [ "$status" -eq 0 ]
    [ "$(git -C "$checkout" rev-parse HEAD)" = "$(git -C "$upstream" rev-parse HEAD)" ]
    [ "$(git config --global --includes alias.envup-lifecycle)" = status ]
    [ "$(git config --global --includes alias.st)" = "status --short" ]
    [ "$(HOME="$second" git config --global --includes user.name)" = "Second User" ]
    cmp "$HOME/.gitconfig.local" "$TEST_HOME/private-before"
    [ -z "$(git -C "$checkout" status --porcelain --untracked-files=no)" ]

    run "$checkout/envup" clean git
    [ "$status" -eq 0 ]
    cmp "$HOME/.gitconfig.local" "$TEST_HOME/private-before"
    run "$checkout/envup" uninstall git --dry-run
    [ "$status" -eq 0 ]
    [ -L "$HOME/.gitconfig" ]
    run "$checkout/envup" uninstall git
    [ "$status" -eq 0 ]
    [ ! -e "$HOME/.gitconfig" ]
    [ ! -L "$HOME/.gitconfig" ]
    [ ! -e "$HOME/.gitconfig.envup" ]
    cmp "$HOME/.gitconfig.local" "$TEST_HOME/private-before"
    [ -f "$ENVUP_BACKUP_DIR/.gitconfig" ]
    [ -L "$second/.gitconfig" ]
    [ "$(HOME="$second" git config --global --includes user.name)" = "Second User" ]
    command -v git >/dev/null
}
