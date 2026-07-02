# shellcheck shell=bash
# shellcheck disable=SC2034  # MODULES is consumed by load_profile() via sourcing
# Profile: standard (default) — typical developer workstation.
# = minimal + terminal tooling.
use_profile minimal
MODULES+=(tmux fzf zoxide atuin)
