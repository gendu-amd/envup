#!/bin/bash
# shellcheck disable=SC2034  # metadata fields are consumed by module_meta() via sourcing
# Module: nvim — Neovim + NvChad. Symlinks ~/.config/nvim; plugins pinned by the
# committed lazy-lock.json.
NAME="nvim"
DESCRIPTION="Neovim editor with NvChad config + lazy.nvim plugins"
DEPENDS=()

# Tools install.sh needs to be on PATH before it can run.
#   git — lazy.nvim clones every plugin; without git the very first
#         `Lazy! restore` would fail.
SELF_DEPS=(git)

# `envup clean nvim` removes plugin/state/cache directories. Useful after:
#   - upgrading nvim across a major version (lua bytecode incompat)
#   - lazy.nvim or mason getting stuck mid-install
# Safe — next `envup install nvim` restores plugins from the committed
# lazy-lock.json (same versions as before).
CLEAN_PATHS=(
    "$HOME/.local/share/nvim"
    "$HOME/.local/state/nvim"
    "$HOME/.cache/nvim"
)
