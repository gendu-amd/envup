# ============================================
# envup — zsh configuration
# ============================================
# Config is split into slices under ~/.zshrc.d/. They load in filename order,
# and the order is the whole design:
#
#   00-guard     p10k instant prompt, early guards
#   10-path      PATH helpers; never reorders what was inherited
#   20-platform  OS detection + platform/<os>.zsh  (brew shellenv lives here)
#   30-env       locale / EDITOR / workspace — every one of them conditional
#   40-shell     Oh-My-Zsh, prompt, history, the one and only compinit
#   50-tools     fzf / zoxide / atuin / direnv     (needs 20's PATH)
#   55-node      nvm, lazily
#   60-alias     aliases, conditional on the binary existing
#   65-func      functions
#   70-host      hosts/<hostname>.zsh — committed per-machine config
#   80-local     ~/.zshrc.local — personal, never committed, wins over all
#   90-tmux      attach to tmux, restoring what the last reboot interrupted
#
# The numbers replaced a hand-maintained list in this file. The list kept the
# order readable but let it be wrong: tools loaded before platform, so on macOS
# every brew-installed tool was invisible to its own init line and zoxide, atuin
# and fzf silently did nothing. A number in the filename is harder to get wrong
# than a sentence in a comment.
#
# To add a slice: drop ~/.zshrc.d/<NN>-<name>.zsh in. Pick NN by what it needs.
# ============================================

# stderr is NOT swallowed here, and there is no "[envup] failed to load
# tools.zsh" wrapper either. The old loader had both, which was the worst of
# each: it hid the real error and replaced it with a line that named the file
# and nothing else. zsh already prefixes its own errors with the file and the
# line number —
#
#     ~/.zshrc.d/50-tools.zsh:14: command not found: zoxide
#
# — so letting them through is strictly more informative than anything this
# loop could add. A slice's exit status is not checked, because a slice ending
# in `[[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh` "fails" whenever that file is
# absent, and warnings that fire when nothing is wrong are how people learn to
# stop reading their shell's output.
#
# ENVUP_ZSH_QUIET=1 restores the silence for a machine that really needs it.
() {
    local f
    for f in "$HOME"/.zshrc.d/[0-9][0-9]-*.zsh(N); do
        if [[ -n "${ENVUP_ZSH_QUIET:-}" ]]; then
            source "$f" 2>/dev/null
        else
            source "$f"
        fi
    done
    return 0
}
