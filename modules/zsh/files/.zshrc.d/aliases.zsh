# ============================================
# Aliases
# ============================================

# ---------------------------
# General
# ---------------------------
alias vim="nvim"
alias vi="nvim"
alias grep="grep --color=auto"
alias df="df -h"
alias du="du -h"

# ---------------------------
# Modern CLI replacements
# ---------------------------
if command -v eza &>/dev/null; then
    alias ls="eza --icons --group-directories-first"
    alias ll="eza -la --icons --group-directories-first --git"
    alias la="eza -a --icons --group-directories-first"
    alias tree="eza --tree --icons"
else
    # macOS ls uses -G for color, Linux uses --color=auto
    if [[ "$(uname)" == "Darwin" ]]; then
        alias ls="ls -G"
    else
        alias ls="ls --color=auto"
    fi
    alias ll="ls -alhF"
    alias la="ls -A"
fi

if command -v bat &>/dev/null; then
    alias cat="bat --style=plain"
elif command -v batcat &>/dev/null; then
    alias cat="batcat --style=plain"
fi

# ---------------------------
# Navigation
# ---------------------------
[[ -n "$WORKSPACE" ]] && alias ws='cd $WORKSPACE'

# ---------------------------
# Git shortcuts
# ---------------------------
alias gs="git status -sb"
alias gd="git diff"
alias gl="git log --oneline -15"
alias gp="git pull"
alias ga="git add"
alias gc="git commit"
alias gco="git checkout"

# ---------------------------
# Development
# ---------------------------
alias py="python3"
alias mk='make -j$(nproc 2>/dev/null || echo 4)'
