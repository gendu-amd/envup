#!/bin/bash
# shellcheck disable=SC2034  # every field here is read by lib/engine.sh
# Readable Git diffs; hooks.sh refreshes git's generated pager config.

NAME="delta"
DESCRIPTION="Syntax-highlighted git diffs with word-level changes"

DEPENDS=(git)

VERIFY_BIN="delta"

PROVIDERS=(system github_release)
GH_REPO="dandavison/delta"

# Most package families call the package git-delta.
PKG_NAMES=(debian:git-delta rhel:git-delta arch:git-delta brew:git-delta)

LINKS=()
CLEAN_PATHS=()
