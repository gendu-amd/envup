# ============================================
# envup — zsh configuration
# ============================================
# Config is split into named slices under ~/.zshrc.d/. They load in the
# explicit order below — order matters:
#   core      Oh-My-Zsh + Powerlevel10k   (prompt must initialise first)
#   env       environment variables / PATH
#   aliases
#   functions
#   tools     fzf / zoxide / atuin / direnv / history / completion
#   platform  OS-specific tweaks          (after tools, so it can override them)
#   nvm       Node version manager (optional)
#   local     per-machine overrides       (gitignored; loads last so it wins)
#
# To add a slice: drop ~/.zshrc.d/<name>.zsh and add <name> to the list below.
# (We load by an explicit list, not a glob, so the order is readable here
# instead of being encoded in opaque numeric filename prefixes.)
# ============================================

() {
    local slice f
    for slice in core env aliases functions tools platform nvm local; do
        f="$HOME/.zshrc.d/$slice.zsh"
        [[ -r "$f" ]] || continue
        source "$f" 2>/dev/null || echo "[envup] warning: failed to load $slice.zsh" >&2
    done
}
