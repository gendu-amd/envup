# ============================================
# Core Configuration
# ============================================
# Powerlevel10k instant prompt + Oh-My-Zsh setup

# ---------------------------
# Powerlevel10k Instant Prompt
# ---------------------------
# Must be at the very top, before any console output
typeset -g POWERLEVEL9K_INSTANT_PROMPT=quiet

if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
    source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# ---------------------------
# Oh My Zsh Configuration
# ---------------------------
export ZSH="${HOME}/.oh-my-zsh"
export ZSH_CACHE_DIR="${HOME}/.cache/zsh"

# Disable compfix security check (for Docker/mounted volumes)
ZSH_DISABLE_COMPFIX=true

# Theme
ZSH_THEME="powerlevel10k/powerlevel10k"

# Plugins
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

# Load Oh My Zsh
if [[ -f "${ZSH}/oh-my-zsh.sh" ]]; then
    source "${ZSH}/oh-my-zsh.sh"
else
    echo "[envup] Oh-My-Zsh not found. Run: envup install zsh" >&2
    # Minimal fallback: basic completion and key bindings
    autoload -U compinit && compinit 2>/dev/null
    bindkey -e
fi

# ---------------------------
# Powerlevel10k Config
# ---------------------------
[[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh
