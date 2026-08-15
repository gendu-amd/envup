#!/bin/bash
# shellcheck disable=SC2034  # every field here is read by lib/engine.sh
# Module: nvim — Neovim + NvChad. Plugins are pinned by the committed
# lazy-lock.json, so a 0.10 host and a 0.11 container get the same plugin set.

NAME="nvim"
DESCRIPTION="Neovim editor with NvChad config + lazy.nvim plugins"
DEPENDS=()

# lazy.nvim clones every plugin; without git the first restore fails.
SELF_DEPS=(git)

VERIFY_BIN="nvim"
VERIFY_MIN_VERSION="0.10"     # NvChad's floor

# The distro package is very often older than 0.10 — Debian stable and RHEL
# both are. When it is, the engine sees the version shortfall and keeps walking
# the chain, so github_release is what actually lands on those machines. It is
# also the only route on a server without root.
PROVIDERS=(system github_release manual)
PKG_DEFAULT="neovim"
GH_REPO="neovim/neovim"
# Neovim will not start without its runtime/ directory, so the release is a
# whole prefix rather than a lone binary.
GH_TREE=1
MANUAL_HINT="install neovim >= 0.10 yourself: brew install neovim / conda install -c conda-forge neovim / build from source"

LINKS=("modules/nvim/files:$HOME/.config/nvim")

# Removable: the next install restores plugins from the committed
# lazy-lock.json, at the same versions.
CLEAN_PATHS=(
    "$HOME/.local/share/nvim"
    "$HOME/.local/state/nvim"
    "$HOME/.cache/nvim"
)
