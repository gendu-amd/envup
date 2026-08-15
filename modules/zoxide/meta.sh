#!/bin/bash
# shellcheck disable=SC2034  # every field here is read by lib/engine.sh
# Module: zoxide — smarter `cd`. Ships as a single static binary, which is why
# the no-root route (github_release) works perfectly well for it.

NAME="zoxide"
DESCRIPTION="Smarter cd — 'z <dir>' to jump, 'zi' to pick interactively"

# The `z`/`zi` shell integration lives in the zsh module's tools slice, so
# zoxide on its own would install a binary nothing calls.
DEPENDS=(zsh)

VERIFY_BIN="zoxide"

# In order of preference. system first (signed, updated with the machine);
# github_release second and it is the one that matters on a server without
# root; the vendor script last, since it decides its own install prefix.
PROVIDERS=(system github_release script)
GH_REPO="ajeetdsouza/zoxide"
SCRIPT_URL="https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh"

LINKS=()

# zoxide's frecency database (~/.local/share/zoxide) is user data, NOT cache —
# it is your accumulated directory history, so clean must never remove it.
CLEAN_PATHS=()
