#!/usr/bin/env bats
# The library is loaded in one place and measured in one place, and both lists
# have to keep matching what is actually on disk.
#
# This exists because they stopped matching without anyone noticing: lint's
# size budget iterated `lib.sh lib/*.sh`, which quietly excused lib/providers/
# from a rule the rest of the library follows, and github_release grew to
# within five lines of the threshold unmeasured. A soft guard that skips files
# is worse than no guard, because it reads like coverage.

load '../test_helper'

setup() { common_setup; }
teardown() { common_teardown; }

_lib_files() { ls "$REPO_ROOT"/lib/*.sh "$REPO_ROOT"/lib/providers/*.sh; }

@test "lint.sh measures every library file, providers included" {
    run bash "$REPO_ROOT/scripts/lint.sh"
    [ "$status" -eq 0 ]
    local f
    while read -r f; do
        # Either a size line or a note — both mean it was looked at.
        echo "$output" | grep -qF "${f#"$REPO_ROOT"/}" || {
            echo "unmeasured: $f"; return 1
        }
    done < <(_lib_files)
}

@test "every library file is inside the size budget" {
    # The budget is lint's to define; read it from there rather than repeating
    # the number and letting the two drift.
    local budget f n over=""
    budget="$(sed -n 's/^lib_threshold=//p' "$REPO_ROOT/scripts/lint.sh" | head -1)"
    [ -n "$budget" ]
    while read -r f; do
        n="$(wc -l < "$f")"
        (( n > budget )) && over="$over ${f#"$REPO_ROOT"/}:$n"
    done < <(_lib_files)
    [ -z "$over" ] || { echo "over $budget lines:$over"; return 1; }
}

@test "lib.sh sources every lib/*.sh by name" {
    # Providers are loaded by a glob on purpose (adding a route is adding a
    # file). Everything else is named, so a new file that nobody sources is a
    # silent no-op — the failure mode that makes a split look like it worked.
    local f base
    for f in "$REPO_ROOT"/lib/*.sh; do
        base="${f##*/}"
        grep -qF "\$_ENVUP_LIB/$base" "$REPO_ROOT/lib.sh" || {
            echo "lib.sh never sources lib/$base"; return 1
        }
    done
}

@test "the verification helpers survive the split out of engine.sh" {
    # lib/verify.sh is what engine, health, doctor and module hooks all call.
    local fn
    for fn in bin_path bin_runs bin_version version_ge engine_verify; do
        declare -F "$fn" >/dev/null || { echo "missing: $fn"; return 1; }
    done
    [ -n "$ENVUP_LOCAL_BIN" ]
}

@test "verify.sh is side-effect free: sourcing it alone touches nothing" {
    # engine_verify runs on `envup status` and `envup doctor`, which are
    # read-only commands. A verify that installs something would make looking
    # at the machine change it.
    local before after
    before="$(find "$HOME" "$ENVUP_STATE_DIR" -mindepth 0 2>/dev/null | sort)"
    ( source "$REPO_ROOT/lib/log.sh"; source "$REPO_ROOT/lib/verify.sh"
      VERIFY_BIN=definitely-not-a-real-binary engine_verify ) || true
    after="$(find "$HOME" "$ENVUP_STATE_DIR" -mindepth 0 2>/dev/null | sort)"
    [ "$before" = "$after" ]
}
