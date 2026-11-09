#!/bin/bash
# shellcheck disable=SC2034  # every field here is read by lib/engine.sh
# Fuzzy finder; zsh owns its key bindings.

NAME="fzf"
DESCRIPTION="Fuzzy finder (Ctrl+T files, Ctrl+R history fallback)"
DEPENDS=()

VERIFY_BIN="fzf"

PROVIDERS=(system github_release git)
GH_REPO="junegunn/fzf"
GIT_URL="https://github.com/junegunn/fzf.git"
GIT_DEST="$HOME/.fzf"

# Do not let the installer append to the managed ~/.zshrc.
GIT_SETUP="./install --key-bindings --completion --no-update-rc --no-bash --no-fish"

LINKS=()
CLEAN_PATHS=()
