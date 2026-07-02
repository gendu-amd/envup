# ============================================
# envup - zsh environment
# ============================================
# This file is sourced FIRST, before /etc/zshrc and ~/.zshrc
#
# Zsh load order:
#   /etc/zshenv → ~/.zshenv (HERE) → /etc/zshrc → ~/.zshrc
#
# We MUST set PATH here because /etc/zshrc sources scripts
# (like /etc/profile.d/*) that require basic commands.
# ============================================

# Ensure basic PATH exists (critical for system scripts)
# Include ~/.local/bin for user-installed tools (fd, bat symlinks, etc.)
export PATH="${HOME}/.local/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin${PATH:+:$PATH}"

# Fix TERM for 256 color support (must be set early for p10k)
# Many Docker images default to TERM=xterm (8 colors only)
if [[ "$TERM" == "xterm" ]]; then
    if [[ -e /usr/share/terminfo/x/xterm-256color ]] || [[ -e /lib/terminfo/x/xterm-256color ]]; then
        export TERM=xterm-256color
    fi
fi
