# ============================================
# Functions
# ============================================

# Create directory and cd into it
mkcd() {
    mkdir -p "$1" && cd "$1"
}

# Extract any archive
extract() {
    if [[ -f "$1" ]]; then
        case "$1" in
            *.tar.bz2) tar xjf "$1" ;;
            *.tar.gz)  tar xzf "$1" ;;
            *.tar.xz)  tar xJf "$1" ;;
            *.bz2)     bunzip2 "$1" ;;
            *.gz)      gunzip "$1" ;;
            *.tar)     tar xf "$1" ;;
            *.tbz2)    tar xjf "$1" ;;
            *.tgz)     tar xzf "$1" ;;
            *.zip)     unzip "$1" ;;
            *.7z)      7z x "$1" ;;
            *)         echo "Unknown format: $1" ;;
        esac
    else
        echo "File not found: $1"
    fi
}

# Jump to a project: fzf over your project roots, then attach-or-create a tmux
# session named after it. Same picker as `prefix + f` inside tmux; from outside
# tmux it attaches instead of switching.
#
# Only defined if the name is free — moreutils also ships a `ts`, and silently
# shadowing someone else's binary is how you lose an afternoon. The script is
# always reachable under its full name.
if [[ -x "$HOME/.local/bin/tmux-sessionizer" ]] && ! command -v ts >/dev/null 2>&1; then
    ts() { "$HOME/.local/bin/tmux-sessionizer" "$@" }
fi

# Terminal size fix for SSH/tmux/Docker
_update_terminal_size() {
    if command -v stty &>/dev/null; then
        local size
        size=$(stty size 2>/dev/null)
        if [[ -n "$size" ]]; then
            export LINES=${size%% *} COLUMNS=${size##* }
        fi
    fi
    # Always succeed — otherwise sourcing this file in a no-TTY context
    # (where `stty size` is empty) makes .zshrc warn "Failed to load functions.zsh".
    return 0
}
trap '_update_terminal_size' WINCH 2>/dev/null
_update_terminal_size
