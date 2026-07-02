#!/bin/bash
# atuin uninstall hook
# atuin has no envup-managed symlinks (its shell hooks load via the zsh
# module's tools.zsh). We never auto-delete ~/.atuin or the history DB at
# ~/.local/share/atuin/ (that's years of your shell history) — just hint.
if [[ -d "$HOME/.atuin" ]]; then
    log_info "atuin dir kept at ~/.atuin — remove manually if desired: rm -rf ~/.atuin"
elif command -v atuin &>/dev/null; then
    log_hint "atuin is on PATH via your package manager; remove with your pkg manager if desired"
fi
log_info "atuin history DB kept at ~/.local/share/atuin/ (remove manually if desired)"
