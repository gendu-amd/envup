#!/bin/bash
# zoxide uninstall hook: no envup-managed symlinks (shell integration lives in
# the zsh module's tools.zsh). We never delete the frecency database at
# ~/.local/share/zoxide — that's your accumulated directory history.
if [[ -x "$HOME/.local/bin/zoxide" ]]; then
    log_info "zoxide binary kept at ~/.local/bin/zoxide — remove manually if desired"
elif command -v zoxide &>/dev/null; then
    log_hint "zoxide is on PATH via your package manager; remove with it if desired"
fi
log_info "zoxide database kept at ~/.local/share/zoxide/ (remove manually if desired)"
