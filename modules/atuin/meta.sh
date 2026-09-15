#!/bin/bash
# shellcheck disable=SC2034  # every field here is read by lib/engine.sh
# SQLite-backed shell history; zsh wires Ctrl-R.

NAME="atuin"
DESCRIPTION="Better shell history (Ctrl+R) with SQLite + fuzzy search"
DEPENDS=(zsh)

VERIFY_BIN="atuin"

# Keep the vendor script last so envup's mirror/proxy path is preferred.
PROVIDERS=(system github_release script)
GH_REPO="atuinsh/atuin"
SCRIPT_URL="https://setup.atuin.sh"

PKG_NAMES=()

# shellcheck disable=SC2016  # evaluated by the engine at install time, not now
APPLIES_IF='[[ "${ENVUP_ATUIN_INSTALL:-}" != skip ]]'

LINKS=()

# History is user data, not cache.
CLEAN_PATHS=()
