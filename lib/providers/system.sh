#!/bin/bash
# ============================================
# provider: system — the machine's own package manager
# ============================================
# First choice everywhere it works: the package is signed, it gets security
# updates, and it costs no network beyond the index the machine already has.
#
# The interesting part is knowing when NOT to try. On a server with no route to
# root this provider must decline immediately and quietly, so the chain moves on
# to a user-space route instead of the run dying inside dpkg.
#
# Depends on: engine.sh, pkg.sh
# ============================================

# provider_system [package-name] — install VERIFY_BIN's package.
provider_system() {
    local want="${1:-$(pkg_name)}"

    # "-" in PKG_NAMES means "this distro has no such package". Saying so is
    # what lets the chain fall through to github_release without a scary error.
    if [[ -z "$want" || "$want" == "-" ]]; then
        log_debug "[$NAME] not packaged for $(pkg_family)"
        return "$ENVUP_RC_UNAVAIL"
    fi
    if ! pkg_can_install; then
        log_debug "[$NAME] system packages unavailable: $(pkg_why_not)"
        return "$ENVUP_RC_UNAVAIL"
    fi

    pkg_install "$want"
}
