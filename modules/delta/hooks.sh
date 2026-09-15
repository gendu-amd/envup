#!/bin/bash
# Refresh git's generated pager config after delta becomes available.

post_install() {
    local hooks="$ENVUP_HOME/modules/git/hooks.sh"
    if [[ ! -f "$hooks" ]]; then
        log_debug "[delta] no git module here; nothing to reconfigure"
        return 0
    fi

    # Isolate git's hook functions from the current module.
    (
        # shellcheck source=/dev/null
        source "$hooks" || exit 1
        _git_write_generated
    ) || {
        log_warn "[delta] could not update ~/.gitconfig.envup" \
                 "— run 'envup install git' to enable delta as git's pager"
        return 0
    }
}

# Uninstall leaves binaries in place, so the pager remains valid.
