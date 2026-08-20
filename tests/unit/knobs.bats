#!/usr/bin/env bats
# Every ENVUP_* name in the code is either documented or declared internal.
#
# There is no third option, and that is the whole point. An environment
# variable is the one part of the interface with no compiler, no signature and
# no caller to keep it honest: you add `${ENVUP_SOMETHING:-default}` in a lib
# file, it works, and nothing anywhere notices that the only person who will
# ever know it exists is you. Twenty-one of them had accumulated that way,
# including where backups go and how to keep a proxy alive through sudo —
# knobs a user on a locked-down machine needs and could not have found.
#
# So the rule is mechanical: a new ENVUP_* fails this test until someone
# decides which it is. Documenting it is one line in the README table; if it
# is plumbing, one line in INTERNAL below, with the reason. Making that
# decision is the deliverable — the test does not care which way it goes.

load '../test_helper'

setup() { common_setup; }
teardown() { common_teardown; }

# Plumbing: real variables that are deliberately not part of the interface.
# Each line says why, because "internal" ages badly without one.
INTERNAL=(
    ENVUP_ARCH_RAW          # uname -m before normalisation; caps.bats forces it
    ENVUP_MANIFEST          # path to the manifest, derived from ENVUP_STATE_DIR
    ENVUP_MANIFEST_SCHEMA   # on-disk manifest format version, bumped by us
    ENVUP_PRIV_ARGV         # the sudo argv caps.sh assembled, for priv_run
    ENVUP_RC_DEGRADED       # ─┐ engine/net/caps exit codes. Callers compare
    ENVUP_RC_NOPRIV         #  │ against the names; nobody sets them from
    ENVUP_RC_OFFLINE        #  │ outside, and a user who did would only be
    ENVUP_RC_SKIPPED        #  │ lying to the status table.
    ENVUP_RC_UNAVAIL        # ─┘
    ENVUP_TS_PAUSE          # set by tmux-sessionizer --launch for itself only
)

# Names the code actually uses. The leading-boundary match keeps _ENVUP_LIB and
# other privately-prefixed locals out — they are not the same namespace.
_code_vars() {
    grep -rhoE '(^|[^A-Za-z0-9_])ENVUP_[A-Z][A-Z0-9_]*' \
        "$REPO_ROOT/envup" "$REPO_ROOT/lib.sh" \
        "$REPO_ROOT/lib" "$REPO_ROOT/modules" \
        "$REPO_ROOT/completions" "$REPO_ROOT/scripts" 2>/dev/null |
        grep -oE 'ENVUP_[A-Z][A-Z0-9_]*' | sed 's/_$//' | sort -u
}

# Names any reader could find. Prose counts — this asks whether the variable is
# discoverable, not whether it sits in a particular table.
_doc_vars() {
    grep -rhoE '(^|[^A-Za-z0-9_])ENVUP_[A-Z][A-Z0-9_]*' \
        "$REPO_ROOT/README.md" "$REPO_ROOT/README.zh-CN.md" \
        "$REPO_ROOT/CONTRIBUTING.md" "$REPO_ROOT/docs" 2>/dev/null |
        grep -oE 'ENVUP_[A-Z][A-Z0-9_]*' | sort -u
}

_is_internal() {
    local v
    for v in "${INTERNAL[@]}"; do [[ "$v" == "$1" ]] && return 0; done
    return 1
}

@test "every ENVUP_* the code uses is documented or declared internal" {
    local v undocumented=()
    while read -r v; do
        [[ -n "$v" ]] || continue
        _is_internal "$v" && continue
        grep -qx "$v" <(_doc_vars) || undocumented+=("$v")
    done < <(_code_vars)

    if (( ${#undocumented[@]} )); then
        printf 'undocumented and not declared internal:\n'
        printf '  %s\n' "${undocumented[@]}"
        printf 'document it in README.md (and README.zh-CN.md), or add it to\n'
        printf 'INTERNAL in %s with the reason.\n' "$BATS_TEST_FILENAME"
        return 1
    fi
}

@test "the docs name no ENVUP_* that the code has dropped" {
    # The other direction, and the one that bites quietly: a variable gets
    # renamed, the README keeps advertising the old name, and the user's export
    # does nothing at all. Nothing about that failure is visible from either side.
    local v phantom=()
    while read -r v; do
        [[ -n "$v" ]] || continue
        grep -qx "$v" <(_code_vars) || phantom+=("$v")
    done < <(_doc_vars)

    if (( ${#phantom[@]} )); then
        printf 'documented but no longer in the code:\n'
        printf '  %s\n' "${phantom[@]}"
        return 1
    fi
}

@test "INTERNAL lists nothing the code has already deleted" {
    local v stale=()
    for v in "${INTERNAL[@]}"; do
        grep -qx "$v" <(_code_vars) || stale+=("$v")
    done

    if (( ${#stale[@]} )); then
        printf 'INTERNAL entries that no longer exist:\n'
        printf '  %s\n' "${stale[@]}"
        return 1
    fi
}

@test "nothing is both documented and declared internal" {
    # A contradiction rather than a gap: the docs promise a knob the code
    # treats as private, so it is one refactor away from being taken out from
    # under someone who read the README and believed it.
    local v both=()
    for v in "${INTERNAL[@]}"; do
        grep -qx "$v" <(_doc_vars) && both+=("$v")
    done

    if (( ${#both[@]} )); then
        printf 'documented, yet listed as internal:\n'
        printf '  %s\n' "${both[@]}"
        printf 'pick one: drop it from INTERNAL, or stop documenting it.\n'
        return 1
    fi
}
