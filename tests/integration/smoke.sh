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

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SMOKE_HOME="$(mktemp -d "${TMPDIR:-/tmp}/envup-smoke.XXXXXX")"
cleanup() { rm -rf "$SMOKE_HOME"; }
trap cleanup EXIT
export HOME="$SMOKE_HOME"

fail() { echo "SMOKE FAIL: $1" >&2; exit 1; }

command -v git >/dev/null 2>&1 || { echo "smoke: git not present, skipping"; exit 0; }

echo "==> install git"
"$REPO_ROOT/envup" install git || fail "install git returned nonzero"
[ -L "$SMOKE_HOME/.gitconfig" ] || fail ".gitconfig symlink not created"
[[ "$(readlink -f "$SMOKE_HOME/.gitconfig")" == "$REPO_ROOT"/* ]] \
    || fail ".gitconfig does not point into the repo"
grep -qx git "$SMOKE_HOME/.local/state/envup/installed" \
    || fail "manifest missing git after install"

echo "==> status"
"$REPO_ROOT/envup" status >/dev/null || fail "status returned nonzero"

echo "==> uninstall git"
"$REPO_ROOT/envup" uninstall git || fail "uninstall git returned nonzero"
[ -e "$SMOKE_HOME/.gitconfig" ] && fail ".gitconfig not removed by uninstall"
[ -f "$SMOKE_HOME/.gitconfig.local" ] || fail ".gitconfig.local (user identity) was not kept"

echo "SMOKE OK (install -> status -> uninstall for git)"
