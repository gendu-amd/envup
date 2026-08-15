# ============================================
# 60 — aliases
# ============================================
# After 20-platform and 50-tools so it can see every binary, and so the
# platform slices no longer need aliases of their own. macos.zsh used to set
# `alias ls="ls -G"` from the platform slice, which ran last and therefore
# overwrote the eza alias set here — on a Mac with eza installed you still got
# BSD ls, with nothing to indicate why.
#
# Rule: an alias that names a binary is conditional on that binary existing.
# `alias vim=nvim` on a server without nvim does not fall back to vim, it makes
# vim unusable.

# ---- editors --------------------------------------------------------------
if (( $+commands[nvim] )); then
    alias vim="nvim"
    alias vi="nvim"
elif (( $+commands[vim] )); then
    alias vi="vim"
fi

# ---- core utils -----------------------------------------------------------
alias grep="grep --color=auto"
alias df="df -h"
alias du="du -h"

if (( $+commands[eza] )); then
    alias ls="eza --icons --group-directories-first"
    alias ll="eza -la --icons --group-directories-first --git"
    alias la="eza -a --icons --group-directories-first"
    alias tree="eza --tree --icons"
else
    # GNU ls takes --color=auto; BSD ls (macOS, without coreutils) takes -G.
    if [[ "$ENVUP_PLATFORM" == macos ]] && ! ls --color=auto / >/dev/null 2>&1; then
        alias ls="ls -G"
    else
        alias ls="ls --color=auto"
    fi
    alias ll="ls -alhF"
    alias la="ls -A"
fi

if (( $+commands[bat] )); then
    alias cat="bat --style=plain"
elif (( $+commands[batcat] )); then
    alias cat="batcat --style=plain"
fi

# ---- navigation -----------------------------------------------------------
[[ -n "${WORKSPACE:-}" ]] && alias ws='cd $WORKSPACE'

# ---- git ------------------------------------------------------------------
if (( $+commands[git] )); then
    alias gs="git status -sb"
    alias gd="git diff"
    alias gl="git log --oneline -15"
    alias gp="git pull"
    alias ga="git add"
    alias gc="git commit"
    alias gco="git checkout"
fi

# ---- development ----------------------------------------------------------
(( $+commands[python3] )) && alias py="python3"
alias mk='make -j$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)'
