#!/usr/bin/env bats
# Manifest: the record of installed modules. add/has/remove/list round-trip,
# plus the schema-2 columns (state / provider / version / time) and the
# repo_root header that lets doctor recognise a moved checkout.

load '../test_helper'

setup() { common_setup; }
teardown() { common_teardown; }

@test "manifest: add then has" {
    run manifest_has zsh; [ "$status" -ne 0 ]
    manifest_add zsh
    run manifest_has zsh; [ "$status" -eq 0 ]
}

@test "manifest: add is idempotent (no duplicate rows)" {
    manifest_add zsh
    manifest_add zsh
    run bash -c "cut -f1 '$ENVUP_MANIFEST' | grep -cx zsh"
    [ "$output" = "1" ]
}

@test "manifest: re-recording a module replaces the old row" {
    manifest_record zoxide ok system 0.9.0
    manifest_record zoxide ok github_release 0.10.0
    run manifest_get zoxide version
    [ "$output" = "0.10.0" ]
    run bash -c "cut -f1 '$ENVUP_MANIFEST' | grep -cx zoxide"
    [ "$output" = "1" ]
}

@test "manifest: remove" {
    manifest_add zsh
    manifest_remove zsh
    run manifest_has zsh; [ "$status" -ne 0 ]
}

@test "manifest: remove keeps the header and the other rows" {
    manifest_record zsh ok system 5.9
    manifest_record git ok system 2.43
    manifest_remove zsh
    run manifest_has git; [ "$status" -eq 0 ]
    run head -1 "$ENVUP_MANIFEST"
    [[ "$output" == "# envup-manifest schema="* ]]
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
    # Schema 1 was the bare module name. Field 1 is still the name, so nothing
    # about reading it changed — that is the entire migration.
    mkdir -p "$ENVUP_STATE_DIR"
    printf 'zsh\ngit\n' > "$ENVUP_MANIFEST"   # pre-schema format
    run manifest_has zsh; [ "$status" -eq 0 ]
    run manifest_list
    [[ "$output" == *zsh* ]] && [[ "$output" == *git* ]]
    # …and its empty columns read as empty rather than as an error.
    run manifest_get zsh provider
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "manifest: records provider and version, and stamps a time" {
    manifest_record fzf ok github_release 0.74.2
    run manifest_get fzf state;    [ "$output" = "ok" ]
    run manifest_get fzf provider; [ "$output" = "github_release" ]
    run manifest_get fzf version;  [ "$output" = "0.74.2" ]
    run manifest_get fzf time
    [[ "$output" == 20*T*Z ]]
}

@test "manifest: degraded is recorded as such, not as ok" {
    # 'installed' used to be one bit, which is how a module whose config landed
    # but whose binary never did looked identical to a working one.
    manifest_record tmux degraded manual ""
    run manifest_get tmux state
    [ "$output" = "degraded" ]
}

@test "manifest: repo_root round-trips and can be rewritten" {
    manifest_add zsh
    run manifest_root
    [ "$output" = "$ENVUP_HOME" ]
    manifest_set_root /moved/elsewhere
    run manifest_root
    [ "$output" = "/moved/elsewhere" ]
    # Rewriting the header must not touch the data.
    run manifest_has zsh; [ "$status" -eq 0 ]
}

@test "manifest: a schema-1 file gains a repo_root header on demand" {
    mkdir -p "$ENVUP_STATE_DIR"
    printf 'zsh\n' > "$ENVUP_MANIFEST"
    manifest_set_root "$ENVUP_HOME"
    run manifest_root
    [ "$output" = "$ENVUP_HOME" ]
    run manifest_list
    [ "$output" = "zsh" ]
}

@test "state: a shared HOME gets one state directory per host" {
    local shared="$TEST_TMP/shared-home"
    mkdir -p "$shared"

    run lib_in_env -u ENVUP_STATE_DIR -u ENVUP_LOG_DIR \
        HOME="$shared" ENVUP_HOME_SHARED=1 ENVUP_HOST=gpu-07 -- \
        'printf "%s\n%s\n" "$ENVUP_STATE_DIR" "$ENVUP_LOG_DIR"'

    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "$shared/.local/state/envup/hosts/gpu-07" ]
    [ "${lines[1]}" = "$shared/.local/state/envup/hosts/gpu-07/logs" ]
}

@test "state: an explicit ENVUP_STATE_DIR is never host-scoped" {
    local chosen="$TEST_TMP/chosen-state"

    run lib_in_env ENVUP_STATE_DIR="$chosen" ENVUP_HOME_SHARED=1 ENVUP_HOST=gpu-07 -- \
        'printf %s "$ENVUP_STATE_DIR"'

    [ "$status" -eq 0 ]
    [ "$output" = "$chosen" ]
}

@test "state: a shared-home host reads the legacy manifest without mutating it" {
    local shared="$TEST_TMP/shared-home" legacy="$TEST_TMP/shared-home/.local/state/envup"
    mkdir -p "$legacy"
    printf 'zsh\n' > "$legacy/installed"

    run lib_in_env -u ENVUP_STATE_DIR -u ENVUP_LOG_DIR \
        HOME="$shared" ENVUP_HOME_SHARED=1 ENVUP_HOST=gpu-07 -- \
        'manifest_list; test ! -e "$ENVUP_STATE_DIR/installed"'

    [ "$status" -eq 0 ]
    [ "$output" = "zsh" ]
}

@test "state: the first manifest write copies legacy state into this host" {
    local shared="$TEST_TMP/shared-home" legacy="$TEST_TMP/shared-home/.local/state/envup"
    local scoped="$legacy/hosts/gpu-07/installed"
    mkdir -p "$legacy"
    printf 'zsh\n' > "$legacy/installed"

    run lib_in_env -u ENVUP_STATE_DIR -u ENVUP_LOG_DIR \
        HOME="$shared" ENVUP_HOME_SHARED=1 ENVUP_HOST=gpu-07 -- \
        'manifest_add git; manifest_list'

    [ "$status" -eq 0 ]
    [[ "$output" == *zsh* ]]
    [[ "$output" == *git* ]]
    [ -f "$scoped" ]
    [ "$(grep -c '^zsh' "$scoped")" -eq 1 ]
    [ "$(grep -c '^git' "$scoped")" -eq 1 ]
    [ -f "$legacy/installed" ]
}

@test "manifest: concurrent writers keep every row" {
    local i
    for i in 1 2 3 4 5 6 7 8 9 10; do
        manifest_record "module-$i" ok test "$i" &
    done
    wait

    run manifest_list
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 10 ]
    for i in 1 2 3 4 5 6 7 8 9 10; do
        printf '%s\n' "$output" | grep -qx "module-$i"
    done
}
