#!/bin/bash
# shellcheck disable=SC2034  # metadata fields are consumed by module_meta() via sourcing
# Module: zsh
# Modern shell with Oh-My-Zsh + Powerlevel10k.

NAME="zsh"
DESCRIPTION="Modern shell with Oh-My-Zsh + Powerlevel10k theme"
DEPENDS=()

# Tools install.sh needs to be on PATH before it can run.
#   git  — for `git submodule update --init --recursive` to fetch p10k +
#          plugins when the user clone'd without --recursive.
#   curl — for the Oh-My-Zsh official installer (also has wget fallback,
#          but curl is the documented one).
SELF_DEPS=(git curl)

# Submodule plugins this module ships, as "name:omz-subdir" pairs. Single
# source of truth shared by install.sh AND uninstall.sh (sourced by both) so
# the two sides can never drift on which plugins exist — previously
# uninstall.sh hardcoded the list and would leak a plugin if install gained
# one. omz-subdir is the Oh-My-Zsh custom/ subdirectory: a prompt theme goes
# in themes/, everything else in plugins/.
ZSH_PLUGINS=(
    "powerlevel10k:themes"
    "zsh-autosuggestions:plugins"
    "zsh-syntax-highlighting:plugins"
)

# `envup clean zsh` resets shell startup caches. Safe to remove anytime;
# they auto-rebuild on next zsh launch (first launch will be slower).
CLEAN_PATHS=(
    "$HOME/.zcompdump"
    "$HOME/.zcompdump-"*
    "$HOME/.cache/p10k-"*
    "$HOME/.cache/gitstatus"
    "$HOME/.oh-my-zsh/cache"
)
