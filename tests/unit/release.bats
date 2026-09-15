#!/usr/bin/env bats
# VERSION, CHANGELOG.md, and Git tags must agree.

load '../test_helper'

setup() { common_setup; }
teardown() { common_teardown; }

CHANGELOG() { printf '%s' "$REPO_ROOT/CHANGELOG.md"; }

# The version numbers of the released sections, newest first. `## [1.2.3] - date`
# only — `## [Unreleased]` is deliberately not one of these.
_released_versions() {
    grep -oE '^## \[[0-9]+\.[0-9]+\.[0-9]+\]' "$(CHANGELOG)" | tr -d '#[] '
}

@test "VERSION is a plain semver number" {
    run cat "$REPO_ROOT/VERSION"
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

@test "VERSION matches the newest released section of the changelog" {
    # The two drift in both directions: bump VERSION and forget the changelog
    # and the release has no notes; write the notes and forget VERSION and
    # every machine reports the previous release for weeks.
    local v top
    v="$(cat "$REPO_ROOT/VERSION")"
    top="$(_released_versions | head -1)"
    [ "$v" = "$top" ] || {
        echo "VERSION says $v, newest changelog section says $top"
        return 1
    }
}

@test "every released section carries a date" {
    local n
    n="$(grep -cE '^## \[[0-9]+\.[0-9]+\.[0-9]+\] - [0-9]{4}-[0-9]{2}-[0-9]{2}$' "$(CHANGELOG)")"
    [ "$n" -eq "$(_released_versions | wc -l)" ]
}

@test "every version heading resolves to a link at the bottom" {
    # The file declares itself Keep a Changelog, whose whole point at the bottom
    # is that a version number is a link to the diff that produced it. A heading
    # with no definition renders as literal brackets — the reader sees a version
    # and has nowhere to click.
    local v
    grep -q '^\[Unreleased\]: http' "$(CHANGELOG)" || {
        echo "no link definition for [Unreleased]"; return 1
    }
    while read -r v; do
        [[ -n "$v" ]] || continue
        grep -q "^\[$v\]: http" "$(CHANGELOG)" || {
            echo "no link definition for [$v]"; return 1
        }
    done < <(_released_versions)
}

@test "every released version has a git tag" {
    # The one that was actually missed. Skipped rather than failed where tags
    # are not available — a CI checkout is shallow and fetches none, and a
    # tarball download is not a git repository at all.
    git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1 || skip "not a git checkout"
    local tags v
    tags="$(git -C "$REPO_ROOT" tag)"
    [[ -n "$tags" ]] || skip "no tags fetched (shallow checkout)"
    while read -r v; do
        [[ -n "$v" ]] || continue
        printf '%s\n' "$tags" | grep -qx "v$v" || {
            echo "CHANGELOG documents $v but there is no v$v tag"; return 1
        }
    done < <(_released_versions)
}

@test "the release checklist in CONTRIBUTING still names these files" {
    # This test enforces the checklist; if the checklist moves on without it,
    # the test is enforcing history.
    grep -q 'CHANGELOG.md' "$REPO_ROOT/CONTRIBUTING.md"
    grep -qE 'git tag' "$REPO_ROOT/CONTRIBUTING.md"
}
