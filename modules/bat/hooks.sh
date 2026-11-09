#!/bin/bash
# Debian/Ubuntu install this binary as batcat; expose a stable `bat` command.

_BAT_SHIM="$ENVUP_LOCAL_BIN/bat"

verify() {
    local b
    for b in bat batcat; do
        bin_path "$b" >/dev/null 2>&1 && bin_runs "$b" && return 0
    done
    return 1
}

post_install() {
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
    # unlink_safe only owns repo links; explicitly reclaim this generated shim.
    if [[ -L "$_BAT_SHIM" && "$(readlink "$_BAT_SHIM")" == */batcat ]]; then
        if [[ "${ENVUP_DRY_RUN:-0}" == 1 ]]; then
            log_info "[dry-run] would remove $_BAT_SHIM"
        else
            rm -f "$_BAT_SHIM" && log_info "[bat] removed the batcat shim $_BAT_SHIM"
        fi
    fi
    return 0
}
