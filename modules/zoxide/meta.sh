#!/bin/bash
# shellcheck disable=SC2034  # every field here is read by lib/engine.sh
# Smarter cd; zsh owns its shell integration.

NAME="zoxide"
DESCRIPTION="Smarter cd — 'z <dir>' to jump, 'zi' to pick interactively"

DEPENDS=(zsh)

VERIFY_BIN="zoxide"

PROVIDERS=(system github_release script)
GH_REPO="ajeetdsouza/zoxide"
SCRIPT_URL="https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh"

LINKS=()

# Frecency history is user data, not cache.
CLEAN_PATHS=()
