#!/usr/bin/env bats
# `envup doctor --authoring` catches module-authoring mistakes against the v2
# contract: meta.sh is data, hooks.sh holds functions, and nothing downloads by
# hand. Uses a fake repo (symlinks to the real envup/lib.sh) with fixture
# modules so broken ones can be injected without touching the real repo.
#
# --authoring, because bare `envup doctor` now health-checks the *machine* —
# see tests/unit/doctor.bats for that half.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    FAKE="$(mktemp -d "${BATS_TMPDIR:-/tmp}/envup-doc.XXXXXX")"
    ln -s "$REPO_ROOT/envup"   "$FAKE/envup"
    ln -s "$REPO_ROOT/lib.sh"  "$FAKE/lib.sh"
    ln -s "$REPO_ROOT/lib"     "$FAKE/lib"
    ln -s "$REPO_ROOT/VERSION" "$FAKE/VERSION"
    mkdir -p "$FAKE/modules/good"
    printf '#!/bin/bash\nNAME="good"\nDESCRIPTION="a good module"\nPROVIDERS=(system manual)\n' \
        > "$FAKE/modules/good/meta.sh"
    printf '#!/bin/bash\npost_install() { :; }\n' > "$FAKE/modules/good/hooks.sh"
}
teardown() {
    [[ -n "${FAKE:-}" && -d "$FAKE" ]] && rm -rf "$FAKE"
    return 0
}

_fixture() {   # _fixture <name> <meta.sh body>
    mkdir -p "$FAKE/modules/$1"
    printf '#!/bin/bash\nNAME="%s"\nDESCRIPTION="x"\n%s\n' "$1" "${2:-}" > "$FAKE/modules/$1/meta.sh"
}

@test "doctor: passes a well-formed module" {
    run "$FAKE/envup" doctor --authoring --module good
    [ "$status" -eq 0 ]
}

@test "doctor: flags a missing DESCRIPTION" {
    mkdir -p "$FAKE/modules/nodesc"
    printf '#!/bin/bash\nNAME="nodesc"\n' > "$FAKE/modules/nodesc/meta.sh"
    run "$FAKE/envup" doctor --authoring --module nodesc
    [ "$status" -ne 0 ]
    [[ "$output" == *"missing DESCRIPTION"* ]]
}

@test "doctor: flags a leftover install.sh from the v1 contract" {
    # Nothing runs install.sh any more, so one left in a module is code that
    # looks live and is not — the worst kind.
    _fixture stale
    printf '#!/bin/bash\n:\n' > "$FAKE/modules/stale/install.sh"
    run "$FAKE/envup" doctor --authoring --module stale
    [ "$status" -ne 0 ]
    [[ "$output" == *"old contract"* ]]
}

@test "doctor: flags a hand-rolled download in a hook" {
    # The mirror, the proxy, the offline check and the timeout all live in
    # lib/net.sh; a bare curl in a module escapes every one of them.
    _fixture rawcurl
    printf '#!/bin/bash\npost_install() { curl -fsSL https://example.com/x | sh; }\n' \
        > "$FAKE/modules/rawcurl/hooks.sh"
    run "$FAKE/envup" doctor --authoring --module rawcurl
    [ "$status" -ne 0 ]
    [[ "$output" == *"net_fetch"* ]]
}

@test "doctor: mentioning curl in a comment is not a finding" {
    _fixture politecurl '#   curl — needed by the vendor installer'
    run "$FAKE/envup" doctor --authoring --module politecurl
    [ "$status" -eq 0 ]
}

@test "doctor: flags an install step run from meta.sh" {
    _fixture actingmeta 'pkg_install something'
    run "$FAKE/envup" doctor --authoring --module actingmeta
    [ "$status" -ne 0 ]
    [[ "$output" == *"declarative"* ]]
}

@test "doctor: flags an unknown provider" {
    _fixture badprov 'PROVIDERS=(system telepathy)'
    run "$FAKE/envup" doctor --authoring --module badprov
    [ "$status" -ne 0 ]
    [[ "$output" == *"unknown provider"* ]]
}

@test "doctor: flags a malformed LINKS entry" {
    _fixture badlink 'LINKS=("modules/badlink/files/x")'
    run "$FAKE/envup" doctor --authoring --module badlink
    [ "$status" -ne 0 ]
    [[ "$output" == *"malformed LINKS"* ]]
}

@test "doctor: flags CLEAN_PATHS that point at user data" {
    mkdir -p "$FAKE/modules/baddata"
    printf '#!/bin/bash\nNAME="baddata"\nDESCRIPTION="x"\nCLEAN_PATHS=("$HOME/.local/share/atuin")\n' \
        > "$FAKE/modules/baddata/meta.sh"
    run "$FAKE/envup" doctor --authoring --module baddata
    [ "$status" -ne 0 ]
    [[ "$output" == *"user data"* ]]
}

# A mistyped contract field is not an error anywhere: the engine reads the name
# it knows, finds it empty, and skips that behaviour. The module looks correct
# and quietly isn't — which is why this needs a linter and not a runtime check.
@test "doctor: flags a meta.sh field the engine never reads" {
    _fixture typo 'VERIFY_BIN="x"
VERIFY_MIN_VER="1.0"'
    run "$FAKE/envup" doctor --authoring --module typo
    [ "$status" -ne 0 ]
    [[ "$output" == *"VERIFY_MIN_VER"* ]]
    [[ "$output" == *"nothing reads"* ]]
}

@test "doctor: a module-private field its own code reads is fine" {
    _fixture privfield 'MY_PLUGINS=(a b)'
    printf '#!/bin/bash\npost_install() { local p; for p in "${MY_PLUGINS[@]}"; do :; done; }\n' \
        > "$FAKE/modules/privfield/hooks.sh"
    run "$FAKE/envup" doctor --authoring --module privfield
    [ "$status" -eq 0 ]
}

# The field list is read out of _engine_load, so adding a field to the contract
# must not turn every module that uses it into a reported typo.
@test "doctor: the contract field list matches what the engine actually resets" {
    run "$FAKE/envup" doctor --authoring
    [ "$status" -eq 0 ]
    local f
    for f in VERIFY_MIN_VERSION GH_ASSET_AVOID GIT_SETUP APPLIES_IF; do
        grep -q "\b$f=" "$REPO_ROOT/lib/engine.sh" || { echo "not reset: $f"; return 1; }
    done
}

# Whichever module installs second wins and the first one's config is simply
# absent, with nothing reported. Only visible with every module in view, so it
# runs on the whole-repo pass rather than per module.
@test "doctor: flags two modules claiming the same link destination" {
    _fixture claimer 'LINKS=("modules/claimer/files/x:$HOME/.contested")'
    _fixture jumper  'LINKS=("modules/jumper/files/x:$HOME/.contested")'
    run "$FAKE/envup" doctor --authoring
    [ "$status" -ne 0 ]
    [[ "$output" == *"already claimed by"* ]]
    [[ "$output" == *".contested"* ]]
}

@test "doctor: the real repo passes clean" {
    run "$REPO_ROOT/envup" doctor --authoring
    [ "$status" -eq 0 ]
}
