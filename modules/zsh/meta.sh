#!/bin/bash
# shellcheck disable=SC2034  # every field here is read by lib/engine.sh
# zsh + Oh-My-Zsh, Powerlevel10k, and completion plugins.

NAME="zsh"
DESCRIPTION="Modern shell with Oh-My-Zsh + Powerlevel10k theme"
DEPENDS=()

SELF_DEPS=(git curl)

VERIFY_BIN="zsh"
PROVIDERS=(system manual)
MANUAL_HINT="ask an admin for the 'zsh' package — envup will link the config regardless"

# Entries are name:Oh-My-Zsh-subdirectory.
ZSH_PLUGINS=(
    "powerlevel10k:themes"
    "zsh-completions:plugins"
    "fzf-tab:plugins"
    "zsh-autosuggestions:plugins"
    "zsh-syntax-highlighting:plugins"
)

LINKS=(
    "modules/zsh/files/.zshenv:$HOME/.zshenv"
    "modules/zsh/files/.zshrc:$HOME/.zshrc"
    "modules/zsh/files/.zshrc.d:$HOME/.zshrc.d"
    "modules/zsh/files/.p10k.zsh:$HOME/.p10k.zsh"
    "modules/zsh/files/.fzf.zsh:$HOME/.fzf.zsh"
    # Put envup on PATH with the shell module.
    "envup:$HOME/.local/bin/envup"
)
for _e in "${ZSH_PLUGINS[@]}"; do
    LINKS+=("modules/zsh/files/plugins/${_e%%:*}:$HOME/.oh-my-zsh/custom/${_e##*:}/${_e%%:*}")
done
unset _e

CLEAN_PATHS=(
    "$HOME/.zcompdump"
    "$HOME/.zcompdump-"*
    "$HOME/.cache/p10k-"*
    "$HOME/.cache/gitstatus"
    "$HOME/.oh-my-zsh/cache"
)
