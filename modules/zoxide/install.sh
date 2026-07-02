#!/bin/bash
# zoxide install hook: install the zoxide binary (package manager first, else
# the official installer into ~/.local/bin). zoxide ships no config files — the
# `z`/`zi` shell integration is wired up by the zsh module's tools.zsh.
#
# Body wrapped in a function so `local` is legal (hooks are sourced into a
# non-function subshell).

_zoxide_install() {
    if pkg_have zoxide; then
        log_info "zoxide already on PATH"; return 0
    fi
    if [[ -x "$HOME/.local/bin/zoxide" ]]; then
        log_info "zoxide found at ~/.local/bin/zoxide"; return 0
    fi
    if [[ "${ENVUP_DRY_RUN:-0}" == 1 ]]; then
        log_info "[dry-run] would install zoxide (via $ENVUP_PKG or official installer)"; return 0
    fi

    # 1. Package manager first — apt (21.04+), dnf, pacman, brew, apk all carry
    # zoxide, and a packaged binary avoids the network-heavy curl installer.
    if pkg_install zoxide && pkg_have zoxide; then
        log_success "zoxide installed (via $ENVUP_PKG)"; return 0
    fi

    # 2. Fallback: official installer drops the binary in ~/.local/bin (already
    # on PATH via the zsh module's env.zsh). curl --connect-timeout + the
    # net_run_logged timeout/kill-after keep a blocked network from hanging.
    log_step "Installing zoxide (official installer)"
    pkg_have curl || { log_error "zoxide install needs curl"; log_hint "install curl, then: envup install zoxide"; return 1; }
    local zox_url; zox_url="$(gh_url https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh)"
    # shellcheck disable=SC2016  # $1 is evaluated by the inner bash -c, not now
    net_run_logged "zoxide installer" -- bash -c \
        'curl --proto "=https" --tlsv1.2 --connect-timeout 10 -sSfL "$1" | sh' _ "$zox_url" \
        || { log_error "zoxide install failed"; log_hint "manual: curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh"; return 1; }

    pkg_have zoxide || [[ -x "$HOME/.local/bin/zoxide" ]] \
        || { log_error "zoxide not found after install"; return 1; }
    log_success "zoxide installed — 'z <dir>' to jump, 'zi' to pick interactively"
}
_zoxide_install
