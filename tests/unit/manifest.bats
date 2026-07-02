#!/usr/bin/env bats
# Manifest: the record of installed modules. add/has/remove/list round-trip.

load '../test_helper'

setup() { common_setup; }
teardown() { common_teardown; }

@test "manifest: add then has" {
    run manifest_has zsh; [ "$status" -ne 0 ]
    manifest_add zsh
    run manifest_has zsh; [ "$status" -eq 0 ]
}

@test "manifest: add is idempotent (no duplicate lines)" {
    manifest_add zsh
    manifest_add zsh
    run bash -c "grep -c '^zsh$' '$ENVUP_MANIFEST'"
    [ "$output" = "1" ]
}

@test "manifest: remove" {
    manifest_add zsh
    manifest_remove zsh
    run manifest_has zsh; [ "$status" -ne 0 ]
}

@test "manifest: list reflects adds" {
    manifest_add zsh
    manifest_add git
    run manifest_list
    [[ "$output" == *zsh* ]]
    [[ "$output" == *git* ]]
}

@test "manifest: a fresh manifest carries a schema header" {
    manifest_add zsh
    run head -1 "$ENVUP_MANIFEST"
    [[ "$output" == "# envup-manifest schema="* ]]
}

@test "manifest: list excludes the header/comment lines" {
    manifest_add zsh
    run manifest_list
    [[ "$output" != *"#"* ]]
    [ "$output" = "zsh" ]
}

@test "manifest: an old headerless manifest is still read" {
    mkdir -p "$ENVUP_STATE_DIR"
    printf 'zsh\ngit\n' > "$ENVUP_MANIFEST"   # pre-schema format
    run manifest_has zsh; [ "$status" -eq 0 ]
    run manifest_list
    [[ "$output" == *zsh* ]] && [[ "$output" == *git* ]]
}
