#!/usr/bin/env bats
# Managed text block: idempotent insert/replace/remove in a file we don't own.

load '../test_helper'

setup() {
    common_setup
    TARGET="$HOME/.bashrc"
    printf 'line1\nline2\n' > "$TARGET"
}
teardown() { common_teardown; }

@test "block_set: inserts a marked block" {
    echo "hello" | block_set "$TARGET" demo
    run grep -c '>>> envup:demo >>>' "$TARGET"
    [ "$output" = "1" ]
    run grep -q "hello" "$TARGET"
    [ "$status" -eq 0 ]
}

@test "block_set: re-setting replaces content without duplicating markers" {
    echo "first"  | block_set "$TARGET" demo
    echo "second" | block_set "$TARGET" demo
    run grep -c '>>> envup:demo >>>' "$TARGET"
    [ "$output" = "1" ]
    run grep -q "second" "$TARGET"; [ "$status" -eq 0 ]
    run grep -q "first"  "$TARGET"; [ "$status" -ne 0 ]
}

@test "block_del: removes the block and leaves the rest intact" {
    echo "hello" | block_set "$TARGET" demo
    block_del "$TARGET" demo
    run grep -q 'envup:demo' "$TARGET"; [ "$status" -ne 0 ]
    run grep -q 'line1' "$TARGET";      [ "$status" -eq 0 ]
}

@test "block_set: dry-run makes no change (I4)" {
    before="$(cat "$TARGET")"
    echo "hello" | ENVUP_DRY_RUN=1 block_set "$TARGET" demo
    [ "$(cat "$TARGET")" = "$before" ]
}
