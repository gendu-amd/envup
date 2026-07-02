#!/bin/bash
# fzf uninstall hook
# fzf has no envup-managed symlinks (its key-bindings load via the zsh module's
# .fzf.zsh). We never auto-delete ~/.fzf — it may predate envup, and removing
# system binaries is out of scope — so just point the user at how to remove it.
if [[ -d "$HOME/.fzf" ]]; then
    log_info "fzf dir kept at ~/.fzf — remove manually if desired: rm -rf ~/.fzf"
elif command -v fzf &>/dev/null; then
    log_hint "fzf is on PATH via your package manager; remove with your pkg manager if desired"
fi
