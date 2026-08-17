#!/bin/bash
# delta hooks: tell git that this machine now has a pager.
#
# ~/.gitconfig.envup is the generated layer — the git module writes it from what
# the machine actually has, which is how one shared .gitconfig can be correct on
# a workstation with delta and on a bare server without it.
#
# The catch is ordering. DEPENDS=(git) puts git first (and every profile does
# too, since git is in minimal), so by the time delta is installed that file has
# already been written — with no [pager] section, because at the moment it was
# written the answer to "is delta here?" was no. Rewriting it is the last step
# of installing delta.

post_install() {
    local hooks="$ENVUP_HOME/modules/git/hooks.sh"
    if [[ ! -f "$hooks" ]]; then
        log_debug "[delta] no git module here; nothing to reconfigure"
        return 0
    fi

    # In a subshell: sourcing that file defines git's own pre_install and
    # post_install, and those must not still be in scope when this one returns —
    # the engine would run git's post_install as if it were delta's.
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

# No post_uninstall on purpose. Removing the delta module does not remove the
# binary — envup only takes back its own symlinks — so delta is still there and
# still the right pager. Rewriting ~/.gitconfig.envup here would turn off a
# feature that still works. If you really want it gone, delete the binary and
# run `envup install git`.
