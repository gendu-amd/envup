#!/bin/bash
# shellcheck disable=SC2034  # every field here is read by lib/engine.sh
# Module: fzf — fuzzy finder. Binary only; the key bindings load from the zsh
# module's .fzf.zsh, which is why there is nothing to link here.

NAME="fzf"
DESCRIPTION="Fuzzy finder (Ctrl+T files, Ctrl+R history fallback)"
DEPENDS=()

VERIFY_BIN="fzf"

# The git route is last because it is the expensive one (a clone plus a build
# script) and it is only needed on a machine with no package and no matching
# release asset.
PROVIDERS=(system github_release git)
GH_REPO="junegunn/fzf"
GIT_URL="https://github.com/junegunn/fzf.git"
GIT_DEST="$HOME/.fzf"

# --no-update-rc is not optional: --all implies --update-rc, which appends
# source lines to ~/.zshrc — a symlink into this repo — and dirties the
# checkout on every install. envup loads fzf from the zsh module instead.
GIT_SETUP="./install --key-bindings --completion --no-update-rc --no-bash --no-fish"

LINKS=()
CLEAN_PATHS=()
