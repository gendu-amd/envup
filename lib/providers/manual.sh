#!/bin/bash
# ============================================
# provider: manual — say what a human would have to do
# ============================================
# The end of the chain for things envup cannot install on this machine: zsh,
# git and tmux need compiling, and on a no-root server with no package for them
# there is no honest automated route.
#
# Guidance does not decide the module's outcome: the engine must retain errors
# from earlier routes and may still try a later automated route.
#
# Depends on: engine.sh
# ============================================

provider_manual() {
    local what="${1:-$VERIFY_BIN}"
    log_warn "[$NAME] $what has to be installed by hand on this machine"
    if [[ -n "${MANUAL_HINT:-}" ]]; then
        log_hint "$MANUAL_HINT"
    else
        log_hint "ask an admin for: $(pkg_name)   (package manager: $ENVUP_PKG, privileges: $ENVUP_PRIV)"
    fi
    log_hint "after installing $what, rerun: envup install $NAME"
    return "$ENVUP_RC_DEGRADED"
}
