#!/bin/bash
# Install Oh-My-Zsh/plugins, then make zsh the interactive default.

_zsh_omz() {
    # An empty ~/.oh-my-zsh directory is not a valid installation.
    [[ -f "$HOME/.oh-my-zsh/oh-my-zsh.sh" ]] && return 0
    if [[ "${ENVUP_DRY_RUN:-0}" == 1 ]]; then
        log_info "[dry-run] would install Oh-My-Zsh"; return 0
    fi

    if [[ -d "$HOME/.oh-my-zsh" ]]; then
        # shellcheck disable=SC2088  # literal ~ is display text, not a path to expand
        log_warn "~/.oh-my-zsh exists but has no oh-my-zsh.sh; moving it aside"
        mv "$HOME/.oh-my-zsh" "$HOME/.oh-my-zsh.envup-bak.$$" \
            || { log_error "could not move the broken ~/.oh-my-zsh aside"; return 1; }
    fi

    log_step "installing Oh-My-Zsh"
    local url="https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh"
    local tmp; tmp="$(mktemp "${TMPDIR:-/tmp}/envup-omz.XXXXXX")" || return 1
    if ! net_fetch "$url" "$tmp"; then
        rm -f "$tmp"
        # Shell config remains usable without Oh-My-Zsh.
        log_warn "could not download the Oh-My-Zsh installer — continuing without it"
        log_hint "re-run 'envup install zsh' once the network is back"
        return 0
    fi
    net_run_logged "oh-my-zsh installer" -- sh "$tmp" --unattended
    local rc=$?
    rm -f "$tmp"
    (( rc == 0 )) || { log_warn "the Oh-My-Zsh installer failed (rc=$rc) — continuing without it"; return 0; }
}

pre_install() {
    _zsh_omz || return 1

    local -a dirs=(); local e
    for e in "${ZSH_PLUGINS[@]}"; do
        dirs+=("$ENVUP_HOME/modules/zsh/files/plugins/${e%%:*}")
    done
    submodule_ensure zsh "${dirs[@]}"
}

# chsh can fail for managed accounts; the bash shim is the fallback.
_zsh_make_default() {
    local zsh_path; zsh_path="$(bin_path zsh)" || return 0

    local current; current="$(getent passwd "$USER" 2>/dev/null | cut -d: -f7)"
    [[ -n "$current" ]] || current="$SHELL"
    if [[ "$current" == "$zsh_path" ]]; then
        log_info "zsh is already your login shell"
    elif [[ "${ENVUP_DRY_RUN:-0}" == 1 ]]; then
        log_info "[dry-run] would set the login shell to zsh where possible"
    elif [[ "$ENVUP_PRIV" == root ]]; then
        # chsh requires /etc/shells; stdin is closed to prevent prompting.
        grep -qxF "$zsh_path" /etc/shells 2>/dev/null || echo "$zsh_path" >>/etc/shells 2>/dev/null
        if chsh -s "$zsh_path" </dev/null >/dev/null 2>&1; then
            log_success "login shell changed to zsh (effective next login)"
        else
            log_warn "chsh failed; the ~/.bashrc shim below covers it"
        fi
    else
        # Never invoke a password-prompting non-root chsh.
        log_info "login shell left as-is (a non-root chsh needs a password)"
        log_hint "to set it yourself: chsh -s $zsh_path"
    fi

    [[ "${ENVUP_DRY_RUN:-0}" == 1 ]] && return 0
    block_set "$HOME/.bashrc" zsh-default <<'SHIM'
# Drop interactive bash into zsh (covers logins where chsh cannot change the
# shell, e.g. LDAP accounts). Escape with: NO_ZSH=1 bash
if [ -z "$ZSH_VERSION" ] && [ -t 1 ] && [ -z "$NO_ZSH" ] && command -v zsh >/dev/null 2>&1; then
    exec zsh
fi
SHIM
    log_info "bash->zsh shim installed in ~/.bashrc (escape: NO_ZSH=1 bash)"
}

post_install() {
    _zsh_make_default
    log_hint "open a new terminal (or 'exec zsh') to load the config"
    log_hint "'envup <Tab>' completes — make sure ~/.local/bin is on PATH"
    return 0
}

post_uninstall() {
    block_del "$HOME/.bashrc" zsh-default
    log_info "removed the bash->zsh shim from ~/.bashrc (the login shell is left as-is)"
    log_info "the zsh package and Oh-My-Zsh are kept"
    log_info "backups, if any: $HOME/.dotfiles_backup/"
    return 0
}
