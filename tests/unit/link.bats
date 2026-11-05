#!/usr/bin/env bats
# I1 (backup-never-clobber) + I2 (idempotent) + I4 (dry-run) for safe_link/_link.

load '../test_helper'

setup() {
    common_setup
    mkdir -p "$ENVUP_HOME/files"
    echo "source-content" > "$ENVUP_HOME/files/foo"
}
teardown() { common_teardown; }

@test "safe_link: creates a symlink at an empty target" {
    run safe_link "files/foo" "$HOME/foo"
    [ "$status" -eq 0 ]
    [ -L "$HOME/foo" ]
    [ "$(readlink -f "$HOME/foo")" = "$(readlink -f "$ENVUP_HOME/files/foo")" ]
}

@test "safe_link: backs up a pre-existing real file before linking (I1)" {
    echo "user-original" > "$HOME/foo"
    run safe_link "files/foo" "$HOME/foo"
    [ "$status" -eq 0 ]
    [ -L "$HOME/foo" ]
    # the user's original content survives in the backup dir
    run grep -rq "user-original" "$ENVUP_BACKUP_DIR"
    [ "$status" -eq 0 ]
}

@test "safe_link: backs up a foreign symlink instead of silently replacing it (I1)" {
    mkdir -p "$HOME/elsewhere"
    ln -s "$HOME/elsewhere" "$HOME/foo"

    safe_link "files/foo" "$HOME/foo"

    [ -L "$HOME/foo" ]
    [ "$(readlink "$HOME/foo")" = "$ENVUP_HOME/files/foo" ]
    [ -L "$ENVUP_BACKUP_DIR/foo" ]
    [ "$(readlink "$ENVUP_BACKUP_DIR/foo")" = "$HOME/elsewhere" ]
}

@test "safe_link: backs up a dangling foreign symlink too (I1)" {
    ln -s "$HOME/no-such-target" "$HOME/foo"

    safe_link "files/foo" "$HOME/foo"

    [ -L "$HOME/foo" ]
    [ -L "$ENVUP_BACKUP_DIR/foo" ]
    [ "$(readlink "$ENVUP_BACKUP_DIR/foo")" = "$HOME/no-such-target" ]
}

@test "safe_link: re-linking an already-correct link is a no-op (I2)" {
    safe_link "files/foo" "$HOME/foo"
    rm -rf "$ENVUP_BACKUP_DIR"
    run safe_link "files/foo" "$HOME/foo"
    [ "$status" -eq 0 ]
    [ -L "$HOME/foo" ]
    # no backup created on the idempotent re-run
    [ ! -d "$ENVUP_BACKUP_DIR" ]
}

# The backup used to be flat, so both of these landed on <backup>/config and
# the second mv destroyed the first user's file with no message at all. That is
# I1 violated by the very code that exists to uphold it.
@test "safe_link: two targets with the same basename both survive backup (I1)" {
    mkdir -p "$HOME/.config/foo" "$HOME/.config/bar"
    echo "foo-original" > "$HOME/.config/foo/config"
    echo "bar-original" > "$HOME/.config/bar/config"

    safe_link "files/foo" "$HOME/.config/foo/config"
    safe_link "files/foo" "$HOME/.config/bar/config"

    run grep -rl "foo-original" "$ENVUP_BACKUP_DIR"
    [ "$status" -eq 0 ]
    run grep -rl "bar-original" "$ENVUP_BACKUP_DIR"
    [ "$status" -eq 0 ]
}

@test "safe_link: the backup mirrors the original path, so it says where it came from" {
    mkdir -p "$HOME/.config/git"
    echo "user-original" > "$HOME/.config/git/ignore"
    safe_link "files/foo" "$HOME/.config/git/ignore"
    [ -f "$ENVUP_BACKUP_DIR/.config/git/ignore" ]
    [ "$(cat "$ENVUP_BACKUP_DIR/.config/git/ignore")" = "user-original" ]
}

@test "backup_path: a target outside \$HOME keeps its full shape" {
    run backup_path "/etc/foo/bar"
    [ "$output" = "$ENVUP_BACKUP_DIR/root/etc/foo/bar" ]
    # ...and cannot collide with a same-named file in $HOME
    run backup_path "$HOME/etc/foo/bar"
    [ "$output" = "$ENVUP_BACKUP_DIR/etc/foo/bar" ]
}

@test "safe_link: dry-run creates nothing (I4)" {
    ENVUP_DRY_RUN=1 run safe_link "files/foo" "$HOME/foo"
    [ "$status" -eq 0 ]
    [ ! -e "$HOME/foo" ]
}

@test "safe_link: legacy directory link cannot move a source file into backup" {
    mkdir -p "$HOME/.config"
    ln -s "$ENVUP_HOME/files" "$HOME/.config/old"

    run safe_link "files/foo" "$HOME/.config/old/foo"
    [ "$status" -ne 0 ]
    [[ "$output" == *"refusing link into checkout"* ]]
    [ ! -L "$ENVUP_HOME/files/foo" ]
    [ "$(cat "$ENVUP_HOME/files/foo")" = source-content ]
    [ ! -e "$ENVUP_BACKUP_DIR" ]
}

@test "safe_link: nested directory aliases cannot replace source trees" {
    mkdir -p "$ENVUP_HOME/files/lua/configs" "$HOME/.config"
    echo original > "$ENVUP_HOME/files/lua/configs/tools.lua"
    ln -s "$ENVUP_HOME/files" "$HOME/.config/old"
    ln -s "$HOME/.config/old" "$HOME/.config/alias"

    run safe_link "files/lua" "$HOME/.config/alias/lua"
    [ "$status" -ne 0 ]
    [ ! -L "$ENVUP_HOME/files/lua" ]
    [ "$(cat "$ENVUP_HOME/files/lua/configs/tools.lua")" = original ]
    [ ! -e "$ENVUP_BACKUP_DIR" ]
}

@test "safe_link: parent aliases cannot modify a different checkout file" {
    echo other > "$ENVUP_HOME/files/other"
    ln -s "$ENVUP_HOME/files" "$HOME/old"

    run safe_link "files/foo" "$HOME/old/other"
    [ "$status" -ne 0 ]
    [ "$(cat "$ENVUP_HOME/files/other")" = other ]
    [ ! -L "$ENVUP_HOME/files/other" ]
    [ ! -e "$ENVUP_BACKUP_DIR" ]
}

@test "safe_link: directory aliases outside the checkout remain supported" {
    mkdir -p "$HOME/config-store"
    ln -s "$HOME/config-store" "$HOME/config"
    echo private > "$HOME/config-store/foo"

    safe_link "files/foo" "$HOME/config/foo"
    [ "$(readlink "$HOME/config-store/foo")" = "$ENVUP_HOME/files/foo" ]
    [ "$(cat "$ENVUP_BACKUP_DIR/config/foo")" = private ]
    [ "$(cat "$ENVUP_HOME/files/foo")" = source-content ]
}

@test "safe_link: missing nested parents cannot bypass checkout protection" {
    ln -s "$ENVUP_HOME/files" "$HOME/old"
    run safe_link "files/foo" "$HOME/old/missing/nested/foo"
    [ "$status" -ne 0 ]
    [ ! -e "$ENVUP_HOME/files/missing" ]
    [ ! -e "$ENVUP_BACKUP_DIR" ]
}

@test "safe_link: dry-run preserves checkout files behind a directory alias" {
    ln -s "$ENVUP_HOME/files" "$HOME/old"
    ENVUP_DRY_RUN=1 run safe_link "files/foo" "$HOME/old/foo"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[dry-run] link"* ]]
    [ "$(cat "$ENVUP_HOME/files/foo")" = source-content ]
    [ ! -e "$ENVUP_BACKUP_DIR" ]
}
