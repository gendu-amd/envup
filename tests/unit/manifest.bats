#!/usr/bin/env bats
# Manifest: the record of installed modules. add/has/remove/list round-trip,
# plus the schema-2 columns (state / provider / version / time) and the
# repo_root header that lets doctor recognise a moved checkout.

load '../test_helper'

setup() { common_setup; }
teardown() { common_teardown; }

_manifest_dump_failure() {
    printf 'bash=%s bats=%s\n' "$BASH_VERSION" "${BATS_VERSION:-unknown}" >&2
    printf 'Final raw manifest:\n' >&2
    if [[ -f "$ENVUP_MANIFEST" ]]; then cat "$ENVUP_MANIFEST" >&2; fi
    printf 'Current manifest_list:\n' >&2
    manifest_list >&2
}

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

@test "manifest: provenance survives a failed retry and old rows remain readable" {
    mkdir -p "$ENVUP_STATE_DIR"
    printf '# envup-manifest schema=2\ngit\tok\tsystem\t2.43\told\n' > "$ENVUP_MANIFEST"
    manifest_record fixture ok github_release 2.0 '/tools with spaces/fixture' abc123 v2.0
    manifest_install_record fixture failed tool 'candidate rejected'
    [ "$(manifest_get fixture path)" = '/tools with spaces/fixture' ]
    [ "$(manifest_get fixture source_revision)" = abc123 ]
    [ "$(manifest_get fixture release_tag)" = v2.0 ]
    [ "$(manifest_get git version)" = 2.43 ]
    [ -z "$(manifest_get git path)" ]
    [ "$(head -1 "$ENVUP_MANIFEST")" = '# envup-manifest schema=3' ]
    manifest_record fixture ok preinstalled 2.0 $'/tools\twith\ncontrols' abc123
    [ "$(manifest_get fixture path)" = '/tools with controls' ]
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
    local i pid
    local -a pids=()
    for i in 1 2 3 4 5 6 7 8 9 10; do
        manifest_record "module-$i" ok test "$i" &
        pids+=("$!")
    done
    for pid in "${pids[@]}"; do
        if ! wait "$pid"; then
            _manifest_dump_failure
            return 1
        fi
    done

    run manifest_list
    [ "$status" -eq 0 ]
    if [ "${#lines[@]}" -ne 10 ]; then
        printf 'Expected 10 modules, got %s:\n%s\n' "${#lines[@]}" "$output" >&2
        _manifest_dump_failure
        return 1
    fi
    for i in 1 2 3 4 5 6 7 8 9 10; do
        printf '%s\n' "$output" | grep -qx "module-$i"
    done
}

@test "manifest: a busy or leftover lock is preserved when waiting expires" {
    mkdir -p "$ENVUP_MANIFEST.lock"
    printf '999999999\n' > "$ENVUP_MANIFEST.lock/pid"
    sleep() { :; }
    run _manifest_lock_acquire
    [ "$status" -eq 1 ]
    [[ "$output" == *"manifest is busy"* ]]
    [ "$(cat "$ENVUP_MANIFEST.lock/pid")" = 999999999 ]
}

@test "manifest: a leftover lock stays busy when mkdir incorrectly succeeds" {
    mkdir -p "$ENVUP_MANIFEST.lock"
    printf '999999999\n' > "$ENVUP_MANIFEST.lock/pid"
    # uutils 0.8.0 can report success after a concurrent mkdir gets EEXIST
    # (uutils/coreutils#13970). Reproduce that return-value contract here.
    mkdir() { command mkdir -p "$@"; }
    sleep() { :; }
    run _manifest_lock_acquire
    [ "$status" -eq 1 ]
    [ "$(cat "$ENVUP_MANIFEST.lock/pid")" = 999999999 ]
}

@test "manifest: an existing file lock is preserved when waiting expires" {
    mkdir -p "$ENVUP_STATE_DIR"
    printf '999999999\n' > "$ENVUP_MANIFEST.lock"
    sleep() { :; }
    run _manifest_lock_acquire
    [ "$status" -eq 1 ]
    [ "$(cat "$ENVUP_MANIFEST.lock")" = 999999999 ]
}

@test "manifest: the writer owns its file lock until the operation returns" {
    check_owner() {
        [ -f "$ENVUP_MANIFEST.lock" ]
        [ "$(cat "$ENVUP_MANIFEST.lock")" = "$BASHPID" ]
    }
    _manifest_with_lock check_owner
    [ ! -e "$ENVUP_MANIFEST.lock" ]
}

@test "manifest: a symlink lock is preserved rather than written through" {
    mkdir -p "$ENVUP_STATE_DIR"
    ln -s /dev/null "$ENVUP_MANIFEST.lock"
    sleep() { :; }
    run _manifest_lock_acquire
    [ "$status" -eq 1 ]
    [ "$(readlink "$ENVUP_MANIFEST.lock")" = /dev/null ]
}

@test "manifest: installation attempts preserve schema-1/2 module rows" {
    mkdir -p "$ENVUP_STATE_DIR"
    printf 'legacy\ntool\tok\tsystem\t1.0\told-time\n' > "$ENVUP_MANIFEST"
    manifest_install_record tool failed post_install $'bad "file"\\name\tline\nnext\033'
    [ "$(manifest_get tool state)" = ok ]
    [ "$(manifest_get tool provider)" = system ]
    [ "$(manifest_get tool version)" = 1.0 ]
    [ "$(manifest_list)" = $'legacy\ntool' ]
    [ "$(manifest_install_get tool state)" = failed ]
    [ "$(manifest_install_get tool phase)" = post_install ]
    local snapshot; snapshot="$(manifest_install_get tool all)"
    [ "$(health_field "$snapshot" state)" = failed ]
    [ "$(health_field "$snapshot" phase)" = post_install ]
    [ "$(manifest_install_get tool reason)" = 'bad "file"\name line next ' ]
    [[ "$(manifest_install_get tool time)" == 20*T*Z ]]
    manifest_install_record tool ok complete ""
    [ "$(manifest_install_get tool state)" = ok ]
    [ "$(manifest_install_list)" = tool ]
}

@test "manifest: a first failed attempt does not become an installed module" {
    manifest_install_record partial failed links "linking failed"
    ! manifest_has partial
    [ -z "$(manifest_list)" ]
    [ "$(manifest_install_list)" = partial ]
    manifest_remove partial
    [ -z "$(manifest_install_list)" ]
}

@test "manifest: dry-run does not write installation attempts" {
    ENVUP_DRY_RUN=1 manifest_install_record partial failed links "linking failed"
    [ ! -e "$ENVUP_MANIFEST" ]
    [ ! -e "$ENVUP_MANIFEST.lock" ]
}

@test "manifest: concurrent attempt and installed-row writers preserve both" {
    local i pid
    local -a pids=()
    for i in 1 2 3 4 5; do
        manifest_record "module-$i" ok test "$i" &
        pids+=("$!")
        manifest_install_record "module-$i" failed post_install "partial config" &
        pids+=("$!")
    done
    for pid in "${pids[@]}"; do
        if ! wait "$pid"; then
            _manifest_dump_failure
            return 1
        fi
    done
    for i in 1 2 3 4 5; do
        if ! manifest_has "module-$i" || [ "$(manifest_install_get "module-$i" state)" != failed ]; then
            printf 'Missing installed row or failed attempt for module-%s\n' "$i" >&2
            _manifest_dump_failure
            return 1
        fi
    done
}
