#!/bin/bash
# Debian/Fedora install this binary as fdfind; expose a stable `fd` command.
_FD_SHIM="$ENVUP_LOCAL_BIN/fd"

verify() {
    local b
    for b in fd fdfind; do
        bin_path "$b" >/dev/null 2>&1 && bin_runs "$b" && return 0
    done
    return 1
}

post_install() {
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
    # unlink_safe only owns repo links; explicitly reclaim this generated shim.
    if [[ -L "$_FD_SHIM" && "$(readlink "$_FD_SHIM")" == */fdfind ]]; then
        if [[ "${ENVUP_DRY_RUN:-0}" == 1 ]]; then
            log_info "[dry-run] would remove $_FD_SHIM"
        else
            rm -f "$_FD_SHIM" && log_info "[fd] removed the fdfind shim $_FD_SHIM"
        fi
    fi
    return 0
}
