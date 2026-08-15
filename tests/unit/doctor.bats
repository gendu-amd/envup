#!/usr/bin/env bats
# `envup doctor` as a *machine* health check (lib/doctor.sh), and `envup adopt`
# (lib/adopt.sh). The authoring checks it used to be are covered by
# tests/integration/doctor.bats.
#
# The distinction under test throughout: an issue is something broken (exit 1,
# --fix can repair it), a note is something worth knowing that is working as
# designed (exit 0). A degraded module on a server without root is a note.

load '../test_helper'

setup() {
    common_setup
    mkdir -p "$ENVUP_HOME/files"
    echo hello > "$ENVUP_HOME/files/thing"
}
teardown() { common_teardown; }

mk_meta() {
    local n="$1"; shift
    mkdir -p "$ENVUP_HOME/modules/$n"
    printf '#!/bin/bash\nNAME="%s"\nDESCRIPTION="fixture"\n%s\n' "$n" "$*" \
        > "$ENVUP_HOME/modules/$n/meta.sh"
}

# A module that is installed and healthy.
mk_installed() {
    mk_meta cfg 'LINKS=("files/thing:$HOME/.thing")'
    ln -s "$ENVUP_HOME/files/thing" "$HOME/.thing"
    manifest_add cfg
    manifest_set_root "$ENVUP_HOME"
}

# ---- the verdict ---------------------------------------------------------

@test "doctor: a healthy machine passes" {
    mk_installed
    run doctor_main
    [ "$status" -eq 0 ]
    [[ "$output" == *"healthy"* ]]
}

@test "doctor: a deleted config is an issue, and exits non-zero" {
    # The acceptance case: rm ~/.zshrc must not still read as installed.
    mk_installed
    rm -f "$HOME/.thing"
    run doctor_main
    [ "$status" -ne 0 ]
    [[ "$output" == *"link missing"* ]]
    [[ "$output" == *"issue(s)"* ]]
}

@test "doctor --fix: rebuilds a deleted link and then passes" {
    mk_installed
    rm -f "$HOME/.thing"
    run doctor_main --fix
    [ "$status" -eq 0 ]
    [ -L "$HOME/.thing" ]

    run doctor_main
    [ "$status" -eq 0 ]
}

@test "doctor --fix: re-checks after repairing, and says so if it did not work" {
    # "I tried to fix it" is a weaker claim than "it is fixed", and only the
    # second pass can make the stronger one.
    mk_installed
    rm -f "$HOME/.thing" "$ENVUP_HOME/files/thing"   # source gone: unfixable
    run doctor_main --fix
    [ "$status" -ne 0 ]
    [[ "$output" == *"re-checking after repair"* ]]
}

@test "doctor: a degraded module is a note, not a failure" {
    # No root, no package, no release asset — the config still landed, and that
    # is the designed outcome. A tool that exits 1 over it gets ignored.
    mk_meta srv 'VERIFY_BIN="definitely-not-a-real-binary"
LINKS=("files/thing:$HOME/.thing")'
    ln -s "$ENVUP_HOME/files/thing" "$HOME/.thing"
    manifest_add srv; manifest_set_root "$ENVUP_HOME"
    run doctor_main
    [ "$status" -eq 0 ]
    [[ "$output" == *degraded* ]]
    [[ "$output" == *"note(s)"* ]]
}

@test "doctor: a manifest entry for a module that no longer exists is an orphan" {
    manifest_add ghost
    manifest_set_root "$ENVUP_HOME"
    run doctor_main
    [ "$status" -ne 0 ]
    [[ "$output" == *"orphan"* ]]
}

@test "doctor --fix: drops the orphan entry" {
    manifest_add ghost
    manifest_set_root "$ENVUP_HOME"
    run doctor_main --fix
    [ "$status" -eq 0 ]
    run manifest_has ghost
    [ "$status" -ne 0 ]
}

@test "doctor: a moved repo is reported once, not as N dangling links" {
    mk_installed
    manifest_set_root "$TEST_TMP/where-the-repo-used-to-be"
    run doctor_main
    [ "$status" -ne 0 ]
    [[ "$output" == *"the repo moved"* ]]
}

@test "doctor --fix: relinks after a move and records the new root" {
    mk_installed
    rm -f "$HOME/.thing"
    manifest_set_root "$TEST_TMP/where-the-repo-used-to-be"
    run doctor_main --fix
    [ "$status" -eq 0 ]
    [ -L "$HOME/.thing" ]
    run manifest_root
    [ "$output" = "$ENVUP_HOME" ]
}

@test "doctor: the user's own file at a link target is reported, never assumed" {
    mk_installed
    rm -f "$HOME/.thing"; echo mine > "$HOME/.thing"
    run doctor_main
    [ "$status" -ne 0 ]
    [[ "$output" == *"link foreign"* ]]
}

@test "doctor --fix: backs up a foreign file instead of clobbering it (I1)" {
    mk_installed
    rm -f "$HOME/.thing"; echo mine > "$HOME/.thing"
    run doctor_main --fix
    [ "$status" -eq 0 ]
    [ -L "$HOME/.thing" ]
    run cat "$ENVUP_BACKUP_DIR/.thing"
    [ "$output" = "mine" ]
}

@test "doctor --module: restricts the check to one module" {
    mk_installed
    manifest_add ghost
    run doctor_main --module cfg
    [ "$status" -eq 0 ]
    [[ "$output" != *"orphan"* ]]
}

@test "doctor: an unknown module name is refused" {
    run doctor_main --module not-a-module
    [ "$status" -ne 0 ]
    [[ "$output" == *"no such module"* ]]
}

@test "doctor: nothing installed is not an error" {
    run doctor_main
    [ "$status" -eq 0 ]
    [[ "$output" == *"nothing installed"* ]]
}

@test "doctor --authoring: still runs the module-contract checks" {
    mkdir -p "$ENVUP_HOME/modules/nodesc"
    printf '#!/bin/bash\nNAME="nodesc"\n' > "$ENVUP_HOME/modules/nodesc/meta.sh"
    run doctor_main --authoring
    [ "$status" -ne 0 ]
    [[ "$output" == *"missing DESCRIPTION"* ]]
}
