# ============================================
# Tools Configuration
# ============================================
# FZF, zoxide, atuin, direnv, history, completion

# ---------------------------
# History Configuration
# ---------------------------
HISTSIZE=50000
SAVEHIST=50000
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_SPACE
setopt SHARE_HISTORY
setopt APPEND_HISTORY
setopt HIST_FIND_NO_DUPS

# ---------------------------
# Zoxide (smarter cd)
# ---------------------------
# Usage: z <pattern> to jump, zi for interactive selection
if command -v zoxide &>/dev/null; then
    eval "$(zoxide init zsh)"
    alias j='z'  # autojump muscle memory
fi

# ---------------------------
# Direnv (directory-level env vars)
# ---------------------------
# Usage: create .envrc in project dir, run `direnv allow`
if command -v direnv &>/dev/null; then
    eval "$(direnv hook zsh)"
fi

# ---------------------------
# FZF Configuration
# ---------------------------
# Role split (intentional, no real overlap):
#   Ctrl-T  fuzzy file picker        — fzf
#   Alt-C   fuzzy directory jump     — fzf
#   **<Tab> fuzzy completion trigger — fzf
#   Ctrl-R  history search           — atuin (loaded last, overrides fzf)
#
# fzf's Ctrl-R bindings are loaded by ~/.fzf.zsh below as a fallback for
# machines without atuin. We deliberately don't set FZF_CTRL_R_OPTS because
# atuin is what users actually hit Ctrl-R on; configuring fzf's Ctrl-R UI
# would just be dead config that confuses anyone reading this file.

export FZF_COMPLETION_TRIGGER='**'

[[ -f ~/.fzf.zsh ]] && source ~/.fzf.zsh

export FZF_DEFAULT_OPTS='--height 40% --layout=reverse --border'
export FZF_CTRL_T_OPTS="--preview 'head -100 {}'"

# Use fd if available (faster than find)
if command -v fd &>/dev/null; then
    export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
    export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
    _fzf_compgen_path() {
        fd --hidden --follow --exclude ".git" . "$1"
    }
    _fzf_compgen_dir() {
        fd --type d --hidden --follow --exclude ".git" . "$1"
    }
elif command -v fdfind &>/dev/null; then
    export FZF_DEFAULT_COMMAND='fdfind --type f --hidden --follow --exclude .git'
    export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
fi

# ---------------------------
# Atuin (better shell history)
# ---------------------------
# Usage: Ctrl+R for interactive history search
# Syncs history across machines (optional, needs account)
# Load env if it exists (for non-standard installs)
[[ -d "$HOME/.atuin/bin" ]] && export PATH="$HOME/.atuin/bin:$PATH"

# MOVED TO END: atuin init overwrites Ctrl-R, so it must be loaded AFTER fzf
if command -v atuin &>/dev/null; then
    eval "$(atuin init zsh --disable-up-arrow)"
fi

# ---------------------------
# envup completion
# ---------------------------
# Find the envup repo root by following the envup executable, then add its
# completions/ dir to fpath so the _envup function loads automatically.
if command -v envup &>/dev/null; then
    _envup_bin=$(whence -p envup 2>/dev/null)
    if [[ -n "$_envup_bin" ]]; then
        _envup_home=$(dirname "$(readlink -f "$_envup_bin" 2>/dev/null || echo "$_envup_bin")")
        if [[ -d "$_envup_home/completions" ]]; then
            fpath=("$_envup_home/completions" $fpath)
            autoload -Uz compinit && compinit -u
        fi
        unset _envup_home
    fi
    unset _envup_bin
fi
