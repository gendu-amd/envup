# shellcheck shell=bash
# shellcheck disable=SC2034  # MODULES is consumed by load_profile() via sourcing
# Profile: standard (default) — typical developer workstation.
# = minimal + terminal tooling.
use_profile minimal
#
# ripgrep and fd come before the things that call them: fzf lists files with fd
# when it can, and nvim's Telescope greps with rg. Both degrade silently rather
# than complain, which is why they are installed rather than left to chance.
#
# bat and eza are the same story one layer up: the zsh module's alias slice has
# always pointed cat/ls/ll at them behind a `commands[...]` guard, and the guard
# has always been false. direnv likewise — 50-tools.zsh evals its hook whenever
# the binary is there, and it never was.
MODULES+=(tmux fzf ripgrep fd bat eza zoxide atuin delta direnv)
