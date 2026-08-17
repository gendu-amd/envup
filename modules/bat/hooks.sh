#!/bin/bash
# bat hooks: reconcile the two names this program goes by.
#
# Debian gave /usr/bin/bat to an unrelated package (bacula-console-qt) before
# this bat existed, so its package installs the binary as `batcat`. Ubuntu
# inherited that. Fedora, Arch, Alpine, brew and every GitHub release asset call
# it `bat`.
#
# This is the same problem as modules/fd, and it goes wrong the same way: without
# this file, `apt-get install bat` reports success, the engine then looks for
# `bat`, finds nothing, records the system provider as having failed, and
# downloads a second copy of the same program from GitHub.
#
# So: verify() accepts either name, and post_install leaves a symlink named
# `bat` in ~/.local/bin. 60-alias.zsh knows about batcat too, but plenty of other
# things do not — fzf's --preview, git's pager, and your own fingers.

_BAT_SHIM="$ENVUP_LOCAL_BIN/bat"

# Side-effect free on purpose: `envup status` and `envup doctor` call this to
# ask a question, and a question must not change the answer.
verify() {
    local b
    for b in bat batcat; do
        bin_path "$b" >/dev/null 2>&1 && bin_runs "$b" && return 0
    done
    return 1
}

post_install() {
    # A real bat — from a package, a release, or one that was already here —
    # needs nothing from us.
    bin_path bat >/dev/null 2>&1 && return 0

    local real
    real="$(command -v batcat 2>/dev/null)" || return 0

    if [[ "${ENVUP_DRY_RUN:-0}" == 1 ]]; then
        log_info "[dry-run] would link $_BAT_SHIM -> $real"
        return 0
    fi

    mkdir -p "$ENVUP_LOCAL_BIN" || return 1
    ln -sf "$real" "$_BAT_SHIM" || {
        log_warn "[bat] could not create $_BAT_SHIM — use 'batcat' on this machine"
        return 0
    }
    log_success "[bat] this distro calls it batcat; linked $_BAT_SHIM -> $real"
}

post_uninstall() {
    # Ours to remove: it points at the distro's binary rather than into the
    # repo, so unlink_safe — which only recognises links into $ENVUP_HOME —
    # would leave it behind, dangling, forever.
    if [[ -L "$_BAT_SHIM" && "$(readlink "$_BAT_SHIM")" == */batcat ]]; then
        if [[ "${ENVUP_DRY_RUN:-0}" == 1 ]]; then
            log_info "[dry-run] would remove $_BAT_SHIM"
        else
            rm -f "$_BAT_SHIM" && log_info "[bat] removed the batcat shim $_BAT_SHIM"
        fi
    fi
    return 0
}
