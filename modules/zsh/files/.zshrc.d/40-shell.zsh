# ============================================
# 40 — shell: Oh-My-Zsh, prompt, history, completion
# ============================================
# compinit runs exactly once, here. It used to run twice — once inside
# oh-my-zsh.sh and again at the bottom of the tools slice to pick up envup's
# completions — which costs 100-300ms of startup, and much more than that on an
# NFS home where every fpath stat crosses the network. The second call also used
# `compinit -u`, which silences the insecure-directory warning rather than
# fixing it.
#
# The fix is ordering, not deletion: fpath gains envup's completions *before*
# Oh-My-Zsh loads, so the one compinit OMZ runs already sees them.

export ZSH="${HOME}/.oh-my-zsh"
export ZSH_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/zsh"
[[ -d "$ZSH_CACHE_DIR" ]] || mkdir -p "$ZSH_CACHE_DIR"

# Containers and mounted volumes routinely have group-writable directories that
# compinit refuses to trust; the alternative to this is a wall of warnings.
ZSH_DISABLE_COMPFIX=true

ZSH_THEME="powerlevel10k/powerlevel10k"

plugins=(
    git
    sudo
    extract
    colored-man-pages
    command-not-found
    vi-mode
    zsh-autosuggestions
    zsh-syntax-highlighting
)

# ---- envup's own completions ---------------------------------------------
# `:A` is zsh's native symlink resolver — no readlink subprocess, and it works
# the same on macOS, where readlink has no -f.
if (( $+commands[envup] )); then
    () {
        local bin="${commands[envup]:A}"
        local root="${bin:h}"
        [[ -d "$root/completions" ]] && fpath=("$root/completions" $fpath)
    }
fi

# ---- history --------------------------------------------------------------
HISTFILE="${HISTFILE:-$HOME/.zsh_history}"
HISTSIZE=50000
SAVEHIST=50000
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_SPACE
setopt SHARE_HISTORY
setopt APPEND_HISTORY
setopt HIST_FIND_NO_DUPS

# ---- Oh-My-Zsh ------------------------------------------------------------
if [[ -f "${ZSH}/oh-my-zsh.sh" ]]; then
    source "${ZSH}/oh-my-zsh.sh"     # runs compinit for us
else
    # No OMZ: an offline install, or a machine where the installer was blocked.
    # The shell still has to work, so do the minimum ourselves — once.
    autoload -Uz compinit
    compinit -d "$ZSH_CACHE_DIR/zcompdump"
    bindkey -e
fi

[[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh
