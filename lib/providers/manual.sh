#!/bin/bash
# ============================================
# provider: manual — say what a human would have to do
# ============================================
# The end of the chain for things envup cannot install on this machine: zsh,
# git and tmux need compiling, and on a no-root server with no package for them
# there is no honest automated route.
#
# It exists so that case produces a *sentence* instead of a stack of failed
# providers. The module still ends up degraded rather than failed — the config
# is linked, and it starts working the day someone installs the package.
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
    log_hint "envup has linked the config anyway — it starts working as soon as $what exists"
    return "$ENVUP_RC_DEGRADED"
}
