# ============================================
# envup — zsh environment
# ============================================
# Sourced FIRST, for every zsh: /etc/zshenv → ~/.zshenv (here) → /etc/zshrc →
# ~/.zshrc. Scripts and ssh commands get this file and nothing else, so it has
# to be cheap and it has to leave the shell usable.
#
# What it must NOT do — and used to:
#
#     export PATH="$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin:...:$PATH"
#
# That puts the system directories in front of everything inherited, which
# quietly demotes brew, conda, pyenv, and HPC `module load` toolchains: `python`
# and `git` resolve to the system copies and the environment you carefully set
# up before starting zsh is ignored. Order is now: whatever you inherited stays
# where it was, and we only *add* what is missing.
# ============================================

# -U keeps the array unique, leftmost-wins. Every later prepend/append is
# therefore idempotent, which is what stops PATH from growing without bound in
# nested shells and tmux panes.
typeset -gU path PATH

# User-space installs (envup's github_release provider lands binaries here)
# do go in front: that is the point of installing them.
[[ -d "$HOME/.local/bin" ]] && path=("$HOME/.local/bin" $path)
() {
    local host="${ENVUP_HOST:-$(hostname -s 2>/dev/null || hostname 2>/dev/null)}" d
    host="${host%%.*}"
    host="${host//[^A-Za-z0-9._-]/_}"
    [[ -n "$host" ]] || host=unknown
    # Installation creates this directory on shared HOME; startup only reads
    # it, avoiding filesystem probes in every non-interactive shell.
    d="${ENVUP_LOCAL_BIN:-$HOME/.local/envup/hosts/$host/bin}"
    if [[ -d "$d" ]]; then
        path=("$d" $path)
    fi
}

# A floor, not a preference: appended, so anything inherited keeps priority.
() {
    local d
    for d in /usr/local/bin /usr/bin /bin /usr/sbin /sbin; do
        [[ -d "$d" ]] && path+=("$d")
    done
}

# 256-colour TERM. Must be early — p10k's instant prompt reads it. Many Docker
# images ship TERM=xterm, which is 8 colours and makes the prompt look broken.
if [[ "$TERM" == "xterm" ]]; then
    if [[ -e /usr/share/terminfo/x/xterm-256color || -e /lib/terminfo/x/xterm-256color ]]; then
        export TERM=xterm-256color
    fi
fi
