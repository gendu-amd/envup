#!/bin/bash
# fzf hooks: ~/.fzf may well predate envup, so uninstall points at it rather
# than deleting it.

post_uninstall() {
    if [[ -d "$HOME/.fzf" ]]; then
        log_info "fzf checkout kept at ~/.fzf — remove it yourself if you want: rm -rf ~/.fzf"
    fi
    return 0
}
