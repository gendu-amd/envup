# ============================================
# 00 — early guards
# ============================================
# Powerlevel10k's instant prompt has to run before anything writes to the
# terminal, so it goes in the first slice and nothing above it may echo.

typeset -g POWERLEVEL9K_INSTANT_PROMPT=quiet

if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
    source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi
