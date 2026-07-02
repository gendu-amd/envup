#!/bin/bash
# fzf install hook
# Prefer official installer (gets latest version + key bindings).
#
# We never auto-remove ~/.fzf on uninstall (it may predate envup); uninstall
# just prints a manual-removal hint. The hook body is wrapped in a function so
# `local` is legal (module hooks are sourced into a non-function subshell).

_fzf_install() {
    if pkg_have fzf; then
        log_info "fzf already on PATH"
        return 0
    fi

    if [[ -d "$HOME/.fzf" ]]; then
        log_info "fzf already installed at ~/.fzf — leaving it as-is"
        return 0
    fi

    if [[ "${ENVUP_DRY_RUN:-0}" == "1" ]]; then
        log_info "[dry-run] would install fzf (via $ENVUP_PKG or git clone)"
        return 0
    fi

    case "$ENVUP_PKG" in
        brew|pacman)
            pkg_install fzf || return 1
            ;;
        *)
            # Official installer needs git + network. Fail gracefully if missing.
            if ! pkg_have git; then
                log_error "fzf install requires 'git' but it isn't on PATH"
                log_hint "Install git manually then retry: envup install fzf"
                return 1
            fi
            log_step "Installing fzf via official installer"
            net_run "fzf clone" -- git clone --depth=1 "$(gh_url https://github.com/junegunn/fzf.git)" "$HOME/.fzf" \
                || {
                    log_error "fzf clone failed (or timed out)"
                    log_hint "Common causes: no network, GitHub blocked, proxy needed, or ~/.fzf already exists"
                    log_hint "Slow network? Raise the budget: ENVUP_NET_TIMEOUT=300 envup install fzf"
                    return 1
                }
            # IMPORTANT: --no-update-rc is required.
            # `--all` would imply --update-rc, which appends fzf source lines
            # to ~/.zshrc — and our ~/.zshrc is a symlink to a version-controlled
            # file, so the installer would dirty the repo on every run.
            # envup's own zsh module already loads fzf via .zshrc.d/tools.zsh.
            log_run "fzf installer" -- "$HOME/.fzf/install" \
                --key-bindings --completion --no-update-rc \
                --no-bash --no-fish \
                || { log_error "fzf install script failed"; return 1; }
            ;;
    esac

    log_success "fzf installed"
}

_fzf_install
