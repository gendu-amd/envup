#!/bin/bash
# fd hooks: reconcile the two names this program goes by.
#
# On Debian and Fedora the package is fd-find and the binary it installs is
# `fdfind` — Debian had already given `fd` to an unrelated program. Everywhere
# else (Arch, brew, Alpine, and every GitHub release asset) it is `fd`.
#
# Without this the module would be quietly broken on exactly the machines most
# likely to be a work server: `apt-get install fd-find` reports success, the
# engine then looks for `fd`, finds nothing, calls the system provider a liar
# in the log and downloads a second copy of the same program from GitHub.
#
# So: verify() accepts either name, and post_install puts a symlink named `fd`
# in ~/.local/bin so the config that calls it — FZF_DEFAULT_COMMAND in the zsh
# module's 50-tools slice, and your own fingers — does not have to care which
# distro this is.

# Where the shim goes. Same directory every other root-free install uses, and
# it is already on PATH by the time a shell reads the tools slice.
_FD_SHIM="$ENVUP_LOCAL_BIN/fd"

# Deliberately side-effect free: `envup status` and `envup doctor` call this to
# ask a question, and a question must not change the answer.
verify() {
    local b
    for b in fd fdfind; do
        bin_path "$b" >/dev/null 2>&1 && bin_runs "$b" && return 0
    done
    return 1
}

post_install() {
    # A real fd — from a package, a release, or one that was already here —
    # needs nothing from us.
    bin_path fd >/dev/null 2>&1 && return 0

    local real
    real="$(command -v fdfind 2>/dev/null)" || return 0

    if [[ "${ENVUP_DRY_RUN:-0}" == 1 ]]; then
        log_info "[dry-run] would link $_FD_SHIM -> $real"
        return 0
    fi

    mkdir -p "$ENVUP_LOCAL_BIN" || return 1
    ln -sf "$real" "$_FD_SHIM" || {
        log_warn "[fd] could not create $_FD_SHIM — use 'fdfind' on this machine"
        return 0
    }
    log_success "[fd] this distro calls it fdfind; linked $_FD_SHIM -> $real"
}

post_uninstall() {
    # Ours to remove: nothing else creates a symlink at this path, and it points
    # at the distro's binary rather than into the repo, so unlink_safe (which
    # only recognises links into $ENVUP_HOME) would leave it dangling forever.
    if [[ -L "$_FD_SHIM" && "$(readlink "$_FD_SHIM")" == */fdfind ]]; then
        if [[ "${ENVUP_DRY_RUN:-0}" == 1 ]]; then
            log_info "[dry-run] would remove $_FD_SHIM"
        else
            rm -f "$_FD_SHIM" && log_info "[fd] removed the fdfind shim $_FD_SHIM"
        fi
    fi
    return 0
}
