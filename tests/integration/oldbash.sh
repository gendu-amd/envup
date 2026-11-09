#!/usr/bin/env bash
# Bash 4.2 catches empty-array + set -u failures hidden by newer Bash.
# CI runs this in centos:7:
#
#   docker run --rm -v "$PWD:/src:ro" --network none centos:7 \
#       bash -c 'cp -r /src /work && cd /work && tests/integration/oldbash.sh'
#
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OLD_HOME="$(mktemp -d "${TMPDIR:-/tmp}/envup-oldbash.XXXXXX")" || exit 1
trap 'rm -rf "$OLD_HOME"' EXIT
export HOME="$OLD_HOME"
export ENVUP_STATE_DIR="$HOME/state" ENVUP_LOG_DIR="$HOME/logs"
export ENVUP_BACKUP_DIR="$HOME/backups" ENVUP_LOCAL_BIN="$HOME/bin" ENVUP_LOCAL_OPT="$HOME/opt"
export ENVUP_PRIV=none ENVUP_NET=offline ENVUP_HOME_SHARED=0 GIT_CONFIG_NOSYSTEM=1
# The CLI shebang and upgrade re-exec must use the interpreter being tested.
mkdir -p "$HOME/bash-bin" || exit 1
ln -s "$BASH" "$HOME/bash-bin/bash" || exit 1
export PATH="$HOME/bash-bin:$PATH"
mkdir -p "$HOME/project" || exit 1
touch "$HOME/project/CMakeLists.txt" || exit 1
cd "$HOME/project" || exit 1

echo "==> $BASH_VERSION"
(( BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 4) )) &&
    echo "    note: 4.4+ tolerates empty-array expansion; run this in centos:7 for real coverage"

rc=0
fail() { echo "OLDBASH FAIL: $*" >&2; rc=1; }

# Machine checks may report missing capabilities or an offline checkout.
run() {
    local label="$1" expected="$2"; shift 2
    local out status
    out="$(timeout -k 5 120 "$@" 2>&1)"; status=$?
    case "$status" in
        124|125|126|127|137|143) fail "$label could not complete (exit $status): $out"; return 1 ;;
    esac
    case "$out" in
        *"unbound variable"*|*"command not found"*|*"syntax error"*|*"bad substitution"*)
            fail "$label: $out"; return 1 ;;
    esac
    if [[ "$status" != "$expected" && ! ( "$expected" == machine && ( "$status" == 0 || "$status" == 1 ) ) ]]; then
        fail "$label exited $status (expected $expected): $out"
        return 1
    fi
    printf '    PASS %s (exit %s)\n' "$label" "$status"
}

# A manifest with a row in it, so `upgrade` reaches the reinstall step rather
# than returning early at "nothing installed to upgrade" — which is where the
# empty-array expansion lives, and why an empty-manifest run never found it.
mkdir -p "$ENVUP_STATE_DIR" || exit 1
printf '# envup-manifest schema=2\n# repo_root=%s\ngit\tok\tsystem\t0\t1970-01-01T00:00:00Z\n' \
    "$REPO_ROOT" > "$ENVUP_STATE_DIR/installed"

run "status"              0 "$REPO_ROOT/envup" status
run "status --json"       0 "$REPO_ROOT/envup" status --json
run "doctor --authoring"  0 "$REPO_ROOT/envup" doctor --authoring
run "doctor"             machine "$REPO_ROOT/envup" doctor
run "clangd status without database" 1 "$REPO_ROOT/envup" clangd status
run "clangd clean"       0 "$REPO_ROOT/envup" clangd clean
run "uninstall without modules" 1 "$REPO_ROOT/envup" uninstall
run "clean --dry-run"     0 "$REPO_ROOT/envup" clean --dry-run
run "install --dry-run"   0 "$REPO_ROOT/envup" install --profile minimal --dry-run
# --keep-going so a checkout that cannot be updated (no remote, no network)
# still reaches the part being tested; ENVUP_DRY_RUN keeps it off the machine.
ENVUP_DRY_RUN=1 run "upgrade" machine "$REPO_ROOT/envup" upgrade --keep-going

printf '[user]\n name = Old Bash User\n email = oldbash@example.com\n' > "$HOME/.gitconfig"
cp "$HOME/.gitconfig" "$HOME/original-before" || exit 1
has_git=0
if command -v git >/dev/null 2>&1; then
    has_git=1
else
    echo "    Git unavailable: checking configuration-only lifecycle"
    cp "$HOME/.gitconfig" "$HOME/.gitconfig.local" || exit 1
fi
run "install git" 0 "$REPO_ROOT/envup" install git || exit 1
[[ -L "$HOME/.gitconfig" ]] || fail "install did not link Git config"
if (( has_git )); then
    [[ "$(git config --global --includes user.name)" == 'Old Bash User' ]] || fail "identity was not preserved"
else
    cmp -s "$HOME/.gitconfig.local" "$HOME/original-before" || fail "install changed private config"
    grep -q $'^git\tdegraded\t' "$ENVUP_STATE_DIR/installed" || fail "missing Git was not recorded as degraded"
fi
cp "$HOME/.gitconfig.local" "$HOME/private-before" || exit 1
run "reinstall git" 0 "$REPO_ROOT/envup" install git
cmp -s "$HOME/.gitconfig.local" "$HOME/private-before" || fail "reinstall changed private config"
run "doctor git" 0 "$REPO_ROOT/envup" doctor --module git
run "clean git" 0 "$REPO_ROOT/envup" clean git
run "uninstall git --dry-run" 0 "$REPO_ROOT/envup" uninstall git --dry-run
[[ -L "$HOME/.gitconfig" ]] || fail "dry-run removed Git config"
run "uninstall git" 0 "$REPO_ROOT/envup" uninstall git
[[ ! -e "$HOME/.gitconfig" && ! -L "$HOME/.gitconfig" ]] || fail "uninstall retained managed link"
[[ ! -e "$HOME/.gitconfig.envup" ]] || fail "uninstall retained generated config"
cmp -s "$HOME/.gitconfig.local" "$HOME/private-before" || fail "cleanup changed private config"
cmp -s "$ENVUP_BACKUP_DIR/.gitconfig" "$HOME/original-before" || fail "original backup was lost"

(( rc == 0 )) && echo "OLDBASH OK ($BASH_VERSION)"
exit "$rc"
