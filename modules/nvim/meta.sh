#!/bin/bash
# shellcheck disable=SC2034  # every field here is read by lib/engine.sh
# Neovim + NvChad with a pinned plugin set.

NAME="nvim"
DESCRIPTION="Neovim + NvChad with pinned plugins and language tools"
DEPENDS=()

SELF_DEPS=(git)

VERIFY_BIN="nvim"
VERIFY_MIN_VERSION="0.10"

PROVIDERS=(system github_release manual)
PKG_DEFAULT="neovim"
GH_REPO="neovim/neovim"
NVIM_LEGACY_TAG="v0.10.4"
NVIM_RELEASE_GLIBC_MIN="2.34"
# Neovim releases require the full runtime tree.
GH_TREE=1
MANUAL_HINT="install neovim >= 0.10 yourself: brew install neovim / conda install -c conda-forge neovim / build from source"

LINKS=("modules/nvim/files:$HOME/.config/nvim")

CLEAN_PATHS=(
    "$HOME/.local/share/nvim"
    "$HOME/.local/state/nvim"
    "$HOME/.cache/nvim"
)
