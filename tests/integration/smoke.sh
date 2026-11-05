#!/usr/bin/env bash
# Integration smoke test: a real install -> status -> uninstall cycle for the
# `git` module — chosen because it needs no network and no submodules, so it
# runs anywhere git is present (CI containers, dev machines).
#
# Exercises the end-to-end invariants: safe_link creates a repo-pointing symlink
# (I1/I2), the manifest records state, and uninstall reverses only envup's own
# links while keeping user data (~/.gitconfig.local) (I3).
#
# Runs entirely inside a throwaway $HOME — never touches the real machine.
set -uo pipefail

REPO_ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)" || exit 1
SMOKE_HOME="$(mktemp -d "${TMPDIR:-/tmp}/envup-smoke.XXXXXX")" || exit 1
cleanup() { rm -rf "$SMOKE_HOME"; }
trap cleanup EXIT
export HOME="$SMOKE_HOME"
export ENVUP_LOCAL_BIN="$HOME/.local/bin" ENVUP_LOCAL_OPT="$HOME/.local/opt"
export ENVUP_STATE_DIR="$HOME/.local/state/envup" ENVUP_LOG_DIR="$HOME/.local/state/envup/logs"
export ENVUP_BACKUP_DIR="$HOME/.dotfiles_backup"
export PATH="$ENVUP_LOCAL_BIN:$PATH"

fail() { echo "SMOKE FAIL: $1" >&2; exit 1; }

command -v git >/dev/null 2>&1 || fail "git is required for smoke"

echo "==> install git"
"$REPO_ROOT/envup" install git || fail "install git returned nonzero"
[ -L "$SMOKE_HOME/.gitconfig" ] || fail ".gitconfig symlink not created"
[[ "$(readlink "$SMOKE_HOME/.gitconfig")" == "$REPO_ROOT/modules/git/files/.gitconfig" ]] \
    || fail ".gitconfig does not point into the repo"
# The manifest is tab-separated since schema 2 (module, state, provider,
# version, time) — the module name is the first field, not the whole line.
cut -f1 "$SMOKE_HOME/.local/state/envup/installed" | grep -qx git \
    || fail "manifest missing git after install"

echo "==> status"
"$REPO_ROOT/envup" status >/dev/null || fail "status returned nonzero"

echo "==> uninstall git"
"$REPO_ROOT/envup" uninstall git || fail "uninstall git returned nonzero"
[ -e "$SMOKE_HOME/.gitconfig" ] && fail ".gitconfig not removed by uninstall"
[ -f "$SMOKE_HOME/.gitconfig.local" ] || fail ".gitconfig.local (user identity) was not kept"

echo "SMOKE OK (install -> status -> uninstall for git)"

# A config link alone cannot detect an executable built for the wrong libc.
# Host/container CI opts into a real pinned release; local smoke stays offline.
if [[ "${ENVUP_SMOKE_RELEASE:-0}" == 1 ]]; then
    echo "==> install pinned zoxide release"
    "$REPO_ROOT/envup" install zoxide --tools locked || fail "install zoxide returned nonzero"
    [ -x "$ENVUP_LOCAL_BIN/zoxide" ] || fail "zoxide release missing"
    "$ENVUP_LOCAL_BIN/zoxide" --version || fail "zoxide cannot run on this platform"
    "$REPO_ROOT/envup" doctor --module zoxide || fail "zoxide doctor returned nonzero"
    echo "SMOKE OK (pinned release executes)"
fi
