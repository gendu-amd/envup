#!/bin/bash
# atuin hooks: seed the new history DB from whatever history already exists.

post_install() {
    local bin
    bin="$(bin_path atuin)" || return 0     # degraded: nothing to import into

    [[ -f "$HOME/.zsh_history" || -f "$HOME/.bash_history" ]] || return 0
    if [[ "${ENVUP_DRY_RUN:-0}" == 1 ]]; then
        log_info "[dry-run] would import existing shell history into atuin"
        return 0
    fi

    # One-time and idempotent (atuin de-dups), but a huge or malformed history
    # file is exactly the kind of thing that hangs, so it gets its own watchdog
    # rather than eating the module's whole budget.
    log_info "importing existing shell history (one-time, atuin de-dups)"
    local t; t="$(timeout_bin)"
    if [[ -n "$t" ]]; then
        log_run "atuin import" -- "$t" -k 5 60 "$bin" import auto \
            || log_warn "atuin import failed or timed out (non-fatal)"
    else
        log_run "atuin import" -- "$bin" import auto || log_warn "atuin import failed (non-fatal)"
    fi
    return 0
}

post_uninstall() {
    [[ -d "$HOME/.atuin" ]] && log_info "atuin dir kept at ~/.atuin — remove it yourself if you want: rm -rf ~/.atuin"
    log_info "atuin history DB kept at ~/.local/share/atuin/ — that is your shell history"
    return 0
}
