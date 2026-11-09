#!/usr/bin/env bats
# I3 — reversibility: unlink_safe removes only envup-owned symlinks, never the
# user's real files or links pointing outside the repo.

load '../test_helper'

setup() {
    common_setup
    mkdir -p "$ENVUP_HOME/files"
    echo "repo" > "$ENVUP_HOME/files/foo"
}
teardown() { common_teardown; }

@test "is_envup_link: true for a link into the repo, false otherwise" {
    ln -s "$ENVUP_HOME/files/foo" "$HOME/inside"
    echo external > "$TEST_TMP/outside.txt"
    ln -s "$TEST_TMP/outside.txt" "$HOME/outside"

    run is_envup_link "$HOME/inside";  [ "$status" -eq 0 ]
    run is_envup_link "$HOME/outside"; [ "$status" -ne 0 ]
}

@test "unlink_safe: removes an envup-owned symlink" {
    ln -s "$ENVUP_HOME/files/foo" "$HOME/foo"
    run unlink_safe "$HOME/foo"
    [ "$status" -eq 0 ]
    [ ! -e "$HOME/foo" ]
}

@test "unlink_safe: refuses to delete a real file (I3)" {
    echo "user-data" > "$HOME/foo"
    run unlink_safe "$HOME/foo"
    [ "$status" -eq 0 ]
    [ -f "$HOME/foo" ]
    [ "$(cat "$HOME/foo")" = "user-data" ]
}

@test "unlink_safe: refuses to delete a link pointing outside the repo (I3)" {
    echo external > "$TEST_TMP/outside.txt"
    ln -s "$TEST_TMP/outside.txt" "$HOME/foo"
    run unlink_safe "$HOME/foo"
    [ "$status" -eq 0 ]
    [ -L "$HOME/foo" ]
}

@test "unlink_safe: dry-run keeps the link (I4)" {
    ln -s "$ENVUP_HOME/files/foo" "$HOME/foo"
    ENVUP_DRY_RUN=1 run unlink_safe "$HOME/foo"
    [ "$status" -eq 0 ]
    [ -L "$HOME/foo" ]
}
