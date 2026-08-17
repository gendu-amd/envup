#!/bin/bash
# tmux hooks: make sure the plugin submodules are actually populated before the
# engine links them. An empty plugin directory is the classic symptom of a
# non-recursive clone, and linking it produces a tmux that silently has no
# plugins — worth failing on.

pre_install() {
    local -a dirs=(); local p
    for p in "${TMUX_PLUGINS[@]}"; do
        dirs+=("$ENVUP_HOME/modules/tmux/files/plugins/$p")
    done
    submodule_ensure tmux "${dirs[@]}"
}

post_install() {
    log_hint "reload: tmux source ~/.tmux.conf (or restart the server)"
    log_hint "jump to a project: prefix f  (or 'ts' from the shell)"
    log_hint "copy to the clipboard of the machine you are sitting at: just yank — see docs/CLIPBOARD.md"
    log_hint "per-machine config: modules/tmux/files/hosts/$ENVUP_HOST.conf (committed) or ~/.tmux.local (private)"
    return 0
}
