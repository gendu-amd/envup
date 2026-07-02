#!/bin/bash
# atuin install hook: install the atuin binary (package manager where available,
# else the official installer), then import existing shell history. atuin's
# shell hook is wired up by the zsh module's tools.zsh.

_atuin_install() {
    # Escape hatch: atuin is nice-to-have, and its official installer is the
    # part that historically hung on slow/blocked networks. ENVUP_ATUIN_INSTALL=skip
    # lets the rest of an install proceed without it.
    if [[ "${ENVUP_ATUIN_INSTALL:-}" == skip ]]; then
        log_info "ENVUP_ATUIN_INSTALL=skip — skipping atuin"; return 0
    fi

    if pkg_have atuin; then
        log_info "atuin already on PATH"
    elif [[ -x "$HOME/.atuin/bin/atuin" ]]; then
        log_info "atuin found at ~/.atuin/bin/atuin"
    elif [[ "${ENVUP_DRY_RUN:-0}" == 1 ]]; then
        log_info "[dry-run] would install atuin (via $ENVUP_PKG or official installer)"
        return 0
    else
        # Package manager first on EVERY platform. atuin is packaged on brew,
        # pacman, dnf (Fedora), apk, and newer apt — a packaged binary skips
        # the network-heavy curl installer that used to hang. Fall back to the
        # official installer only when the package isn't available.
        if pkg_install atuin && pkg_have atuin; then
            log_info "atuin installed (via $ENVUP_PKG)"
        else
            log_info "atuin not packaged for $ENVUP_PKG — using official installer"
            _atuin_official || return 1
        fi
    fi

    local bin; bin=$(command -v atuin || echo "$HOME/.atuin/bin/atuin")
    pkg_have atuin || [[ -x "$bin" ]] || { log_error "atuin not found after install"; return 1; }

    # Import existing history (one-time, atuin de-dups). Wrap in a timeout —
    # a malformed/huge history file shouldn't be able to wedge the install.
    if [[ -f "$HOME/.zsh_history" || -f "$HOME/.bash_history" ]]; then
        log_info "importing existing shell history (one-time, atuin de-dups)"
        local t; t=$(_net_timeout_bin)
        if [[ -n "$t" ]]; then
            log_run "atuin import" -- "$t" -k 5 60 "$bin" import auto || log_warn "atuin import failed/timed out (non-fatal)"
        else
            log_run "atuin import" -- "$bin" import auto || log_warn "atuin import failed (non-fatal)"
        fi
    fi
    log_success "atuin installed — press Ctrl+R after restarting your shell"
}

# The official installer appends an init block to your shell rc files. ~/.zshrc
# is an envup symlink into the repo, so we temporarily swap aside any rc that is
# OUR symlink during the install, then restore it (trap = restore even if the
# installer is interrupted). Files that aren't envup-managed we leave alone.
_atuin_official() {
    pkg_have curl || { log_error "atuin install needs curl"; log_hint "install curl, then: envup install atuin"; return 1; }
    log_step "Installing atuin (official installer)"

    local -a shielded=(); local f
    for f in "$HOME/.zshrc" "$HOME/.zshenv" "$HOME/.bashrc" "$HOME/.profile"; do
        is_envup_link "$f" || continue
        mv "$f" "$f.envup-bak" && : >"$f" && shielded+=("$f")
    done
    _atuin_restore() { local x; for x in "${shielded[@]+"${shielded[@]}"}"; do rm -f "$x"; mv "$x.envup-bak" "$x"; done; }
    trap _atuin_restore EXIT INT TERM HUP

    # --connect-timeout makes a blocked/black-holed network fail in seconds
    # instead of stalling until net_run_logged's outer timeout fires; the outer
    # timeout -k still backstops the tarball download the installer itself does.
    net_run_logged "atuin installer" -- bash -c \
        'curl --proto "=https" --tlsv1.2 --connect-timeout 10 -LsSf https://setup.atuin.sh | sh'
    local rc=$?
    _atuin_restore; trap - EXIT INT TERM HUP

    if (( rc != 0 )); then
        log_error "atuin install failed (rc=$rc — network/proxy block or timeout?)"
        log_hint "behind a proxy/VPN? raise the budget: ENVUP_NET_TIMEOUT_INSTALLER=600 envup install atuin"
        log_hint "or skip it for now:               ENVUP_ATUIN_INSTALL=skip envup install"
        log_hint "or install manually: curl --proto '=https' --tlsv1.2 -LsSf https://setup.atuin.sh | sh"
        return 1
    fi
}
_atuin_install
