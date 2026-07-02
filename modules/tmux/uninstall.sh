#!/bin/bash
# tmux uninstall hook
#
# Source the shared TMUX_PLUGINS list from meta.sh (see install.sh's matching
# note) so install + uninstall can never drift on which plugins exist.
# `run_module_hook` cd's into the module dir before sourcing, so the relative
# path is safe. Function-wrapped per the module-hook discipline.
# shellcheck source=meta.sh
source ./meta.sh

_tmux_uninstall() {
    unlink_safe "$HOME/.tmux.conf"
    local plugin
    for plugin in "${TMUX_PLUGINS[@]}"; do
        unlink_safe "$HOME/.tmux/plugins/$plugin"
    done
}
_tmux_uninstall
