#!/usr/bin/env bats
# WI-3.2: `envup doctor` catches module-authoring mistakes. Uses a fake repo
# (symlinks to the real envup/lib.sh) with fixture modules so we can inject
# broken ones without touching the real repo.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    FAKE="$(mktemp -d "${BATS_TMPDIR:-/tmp}/envup-doc.XXXXXX")"
    ln -s "$REPO_ROOT/envup"   "$FAKE/envup"
    ln -s "$REPO_ROOT/lib.sh"  "$FAKE/lib.sh"
    ln -s "$REPO_ROOT/VERSION" "$FAKE/VERSION"
    mkdir -p "$FAKE/modules/good"
    printf '#!/bin/bash\nNAME="good"\nDESCRIPTION="a good module"\n' > "$FAKE/modules/good/meta.sh"
    printf '#!/bin/bash\n_i(){ local x=1; :; }\n_i\n' > "$FAKE/modules/good/install.sh"
    printf '#!/bin/bash\n_u(){ :; }\n_u\n'            > "$FAKE/modules/good/uninstall.sh"
}
teardown() {
    [[ -n "${FAKE:-}" && -d "$FAKE" ]] && rm -rf "$FAKE"
    return 0
}

@test "doctor: passes a well-formed module" {
    run "$FAKE/envup" doctor --module good
    [ "$status" -eq 0 ]
}

@test "doctor: flags a missing DESCRIPTION" {
    mkdir -p "$FAKE/modules/nodesc"
    printf '#!/bin/bash\nNAME="nodesc"\n' > "$FAKE/modules/nodesc/meta.sh"
    run "$FAKE/envup" doctor --module nodesc
    [ "$status" -ne 0 ]
    [[ "$output" == *"missing DESCRIPTION"* ]]
}

@test "doctor: flags a top-level local in a hook" {
    mkdir -p "$FAKE/modules/badlocal"
    printf '#!/bin/bash\nNAME="badlocal"\nDESCRIPTION="x"\n' > "$FAKE/modules/badlocal/meta.sh"
    printf '#!/bin/bash\nlocal oops=1\n' > "$FAKE/modules/badlocal/install.sh"
    run "$FAKE/envup" doctor --module badlocal
    [ "$status" -ne 0 ]
    [[ "$output" == *"top-level 'local'"* ]]
}

@test "doctor: flags CLEAN_PATHS that point at user data" {
    mkdir -p "$FAKE/modules/baddata"
    printf '#!/bin/bash\nNAME="baddata"\nDESCRIPTION="x"\nCLEAN_PATHS=("$HOME/.local/share/atuin")\n' \
        > "$FAKE/modules/baddata/meta.sh"
    run "$FAKE/envup" doctor --module baddata
    [ "$status" -ne 0 ]
    [[ "$output" == *"user data"* ]]
}

@test "doctor: the real repo passes clean" {
    run "$REPO_ROOT/envup" doctor
    [ "$status" -eq 0 ]
}
