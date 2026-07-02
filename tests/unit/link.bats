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

@test "safe_link: re-linking an already-correct link is a no-op (I2)" {
    safe_link "files/foo" "$HOME/foo"
    rm -rf "$ENVUP_BACKUP_DIR"
    run safe_link "files/foo" "$HOME/foo"
    [ "$status" -eq 0 ]
    [ -L "$HOME/foo" ]
    # no backup created on the idempotent re-run
    [ ! -d "$ENVUP_BACKUP_DIR" ]
}

@test "safe_link: dry-run creates nothing (I4)" {
    ENVUP_DRY_RUN=1 run safe_link "files/foo" "$HOME/foo"
    [ "$status" -eq 0 ]
    [ ! -e "$HOME/foo" ]
}
