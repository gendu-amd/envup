# ============================================
# 50 — interactive tools
# ============================================
# Loaded after 20-platform, which is the fix for the oldest bug in this config:
# on macOS the tools come from brew, brew is put on PATH by `brew shellenv` in
# the platform slice, and this slice used to run first. Every `command -v
# zoxide` returned nothing, so `z` did not exist, atuin did not bind Ctrl-R, and
# fzf's key bindings were absent — with no error anywhere to explain it.

# ---- zoxide ---------------------------------------------------------------
if (( $+commands[zoxide] )); then
    eval "$(zoxide init zsh)"
    alias j='z'      # autojump muscle memory
fi

# ---- direnv ---------------------------------------------------------------
(( $+commands[direnv] )) && eval "$(direnv hook zsh)"

# ---- fzf ------------------------------------------------------------------
# Role split (intentional, no real overlap):
#   Ctrl-T  fuzzy file picker        — fzf
#   Alt-C   fuzzy directory jump     — fzf
#   **<Tab> fuzzy completion trigger — fzf
#   Ctrl-R  history search           — atuin, loaded last so it wins
#
# fzf's own Ctrl-R binding stays as the fallback for machines without atuin,
# which is why FZF_CTRL_R_OPTS is deliberately unset: configuring a UI almost
# nobody sees is just dead config for the next reader to puzzle over.
export FZF_COMPLETION_TRIGGER='**'
export FZF_DEFAULT_OPTS='--height 40% --layout=reverse --border'
export FZF_CTRL_T_OPTS="--preview 'head -100 {}'"

[[ -f ~/.fzf.zsh ]] && source ~/.fzf.zsh

if (( $+commands[fd] )); then
    export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
    export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
    _fzf_compgen_path() { fd --hidden --follow --exclude ".git" . "$1" }
    _fzf_compgen_dir()  { fd --type d --hidden --follow --exclude ".git" . "$1" }
elif (( $+commands[fdfind] )); then
    # Debian and Fedora ship fd as fdfind: the binary name collides with an
    # unrelated package.
    export FZF_DEFAULT_COMMAND='fdfind --type f --hidden --follow --exclude .git'
    export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
fi

# ---- atuin ----------------------------------------------------------------
# Last, on purpose: `atuin init` rebinds Ctrl-R and must land on top of fzf's.
path_prepend "$HOME/.atuin/bin"
(( $+commands[atuin] )) && eval "$(atuin init zsh --disable-up-arrow)"
