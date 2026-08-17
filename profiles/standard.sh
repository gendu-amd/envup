# shellcheck shell=bash
# shellcheck disable=SC2034  # MODULES is consumed by load_profile() via sourcing
# Profile: standard (default) — typical developer workstation.
# = minimal + terminal tooling.
use_profile minimal
#
# ripgrep and fd come before the things that call them: fzf lists files with fd
# when it can, and nvim's Telescope greps with rg. Both degrade silently rather
# than complain, which is why they are installed rather than left to chance.
MODULES+=(tmux fzf ripgrep fd zoxide atuin delta)
