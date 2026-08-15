#!/bin/bash
# shellcheck disable=SC2034  # every field here is read by lib/engine.sh
# Module: zsh — the shell itself plus Oh-My-Zsh and Powerlevel10k.

NAME="zsh"
DESCRIPTION="Modern shell with Oh-My-Zsh + Powerlevel10k theme"
DEPENDS=()

#   git  — submodules for the theme and the plugins
#   curl — the Oh-My-Zsh installer
SELF_DEPS=(git curl)

VERIFY_BIN="zsh"
# zsh needs compiling; there is no sane user-space binary route. On a server
# without it and without root the module goes 'degraded': every config file is
# linked and correct, and the shell works the moment the package appears.
PROVIDERS=(system manual)
MANUAL_HINT="ask an admin for the 'zsh' package — envup will link the config regardless"

# Submodule plugins this module ships, as "name:omz-subdir". A prompt theme
# goes in themes/, everything else in plugins/.
ZSH_PLUGINS=(
    "powerlevel10k:themes"
    "zsh-autosuggestions:plugins"
    "zsh-syntax-highlighting:plugins"
)

LINKS=(
    "modules/zsh/files/.zshenv:$HOME/.zshenv"
    "modules/zsh/files/.zshrc:$HOME/.zshrc"
    "modules/zsh/files/.zshrc.d:$HOME/.zshrc.d"
    "modules/zsh/files/.p10k.zsh:$HOME/.p10k.zsh"
    "modules/zsh/files/.fzf.zsh:$HOME/.fzf.zsh"
    # envup itself on PATH, so `envup` and its completion work from anywhere.
    # It rides with the zsh module because every non-trivial profile has zsh.
    "envup:$HOME/.local/bin/envup"
)
for _e in "${ZSH_PLUGINS[@]}"; do
    LINKS+=("modules/zsh/files/plugins/${_e%%:*}:$HOME/.oh-my-zsh/custom/${_e##*:}/${_e%%:*}")
done
unset _e

# Startup caches. Safe to remove — they rebuild on the next zsh launch.
CLEAN_PATHS=(
    "$HOME/.zcompdump"
    "$HOME/.zcompdump-"*
    "$HOME/.cache/p10k-"*
    "$HOME/.cache/gitstatus"
    "$HOME/.oh-my-zsh/cache"
)
