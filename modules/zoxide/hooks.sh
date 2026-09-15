#!/bin/bash
# zoxide has no config of its own: everything it needs is the binary plus the
# `eval "$(zoxide init zsh)"` in the zsh module. All that is left is being clear
# about what uninstall deliberately does not delete.

post_uninstall() {
    log_info "zoxide database kept at ~/.local/share/zoxide/ — that is your directory history"
    log_hint "remove it yourself if you really want a clean slate"
}
