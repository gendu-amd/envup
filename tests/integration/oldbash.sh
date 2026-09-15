#!/usr/bin/env bash
# Bash 4.2 catches empty-array + set -u failures hidden by newer Bash.
# CI runs this in centos:7:
#
#   docker run --rm -v "$PWD:/src:ro" --network none centos:7 \
#       bash -c 'cp -r /src /work && cd /work && tests/integration/oldbash.sh'
#
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OLD_HOME="$(mktemp -d "${TMPDIR:-/tmp}/envup-oldbash.XXXXXX")"
trap 'rm -rf "$OLD_HOME"' EXIT
export HOME="$OLD_HOME"

echo "==> $BASH_VERSION"
(( BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 4) )) &&
    echo "    note: 4.4+ tolerates empty-array expansion; run this in centos:7 for real coverage"

rc=0
fail() { echo "OLDBASH FAIL: $*" >&2; rc=1; }

# run <label> <argv...> — the command must neither hang nor emit a shell
# diagnostic. Exit codes are deliberately not asserted: several of these are
# allowed to report a problem with the machine, and none may report one with
# themselves.
run() {
    local label="$1"; shift
    local out; out="$(timeout 120 "$@" 2>&1)"
    case "$?" in 124) fail "$label hung" ; return ;; esac
    case "$out" in
        *"unbound variable"*|*"command not found"*|*"syntax error"*|*"bad substitution"*)
            fail "$label: $(printf '%s\n' "$out" | grep -m1 -E 'unbound variable|command not found|syntax error|bad substitution')" ;;
    esac
}

# A manifest with a row in it, so `upgrade` reaches the reinstall step rather
# than returning early at "nothing installed to upgrade" — which is where the
# empty-array expansion lives, and why an empty-manifest run never found it.
mkdir -p "$OLD_HOME/.local/state/envup"
printf '# envup-manifest schema=2\n# repo_root=%s\ngit\tok\tsystem\t0\t1970-01-01T00:00:00Z\n' \
    "$REPO_ROOT" > "$OLD_HOME/.local/state/envup/installed"

run "status"              "$REPO_ROOT/envup" status
run "status --json"       "$REPO_ROOT/envup" status --json
run "doctor --authoring"  "$REPO_ROOT/envup" doctor --authoring
run "clean --dry-run"     "$REPO_ROOT/envup" clean --dry-run
run "install --dry-run"   "$REPO_ROOT/envup" install --profile minimal --dry-run
# --keep-going so a checkout that cannot be updated (no remote, no network)
# still reaches the part being tested; ENVUP_DRY_RUN keeps it off the machine.
ENVUP_DRY_RUN=1 run "upgrade" "$REPO_ROOT/envup" upgrade --keep-going

(( rc == 0 )) && echo "OLDBASH OK ($BASH_VERSION)"
exit "$rc"
