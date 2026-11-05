# shellcheck shell=bash
# shellcheck disable=SC2034  # MODULES is consumed by load_profile() via sourcing
# Profile: standard (default) — typical developer workstation.
use_profile minimal
MODULES+=(tmux fzf ripgrep fd bat eza zoxide atuin delta direnv jq tealdeer)
