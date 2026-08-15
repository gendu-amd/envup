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
    log_hint "save/restore a session by hand: prefix Ctrl-s / prefix Ctrl-r"
    log_hint "per-machine overrides go in ~/.tmux.local (gitignored)"
    return 0
}
