#!/bin/bash
# zsh install hook
#
# Steps:
#   1. Install zsh package via system pkg manager
#   2. Install Oh-My-Zsh into ~/.oh-my-zsh
#   3. Initialize git submodules for theme + plugins
#   4. Symlink config files into ~/
#   5. Expose `envup` on ~/.local/bin
#
# IMPORTANT: the whole hook body is wrapped in `_zsh_install()` so that
# `local` is legal at every step. Module hooks are sourced into a subshell
# by `run_module_hook`, but the subshell is NOT a function context, so
# `local` at the top level fails with
#     local: can only be used in a function
# This wrap matches the pattern used in atuin/nvim and is enforced for all
# new modules (see CONTRIBUTING.md).
#
# safe_link always backs up a pre-existing real file at the target into
# ~/.dotfiles_backup/<ts>/ before linking — no per-call handling needed here.
#
# ZSH_PLUGINS (the single source of truth for shipped plugins, as
# "name:omz-subdir" pairs) lives in meta.sh — shared with uninstall.sh so the
# two can never drift. `run_module_hook` cd's into the module dir before
# sourcing this script, so the relative path is safe.
# shellcheck source=meta.sh
source ./meta.sh

_zsh_install() {
    # Plugin names, derived from the shared ZSH_PLUGINS pairs.
    local -a PLUGINS=()
    local _entry
    for _entry in "${ZSH_PLUGINS[@]}"; do PLUGINS+=("${_entry%%:*}"); done

    # 1. system package
    if ! pkg_have zsh; then
        pkg_install zsh || return 1
    fi

    # 2. Oh-My-Zsh (skip only if the real entry-point file is present —
    # checking the directory alone is not enough: a leftover empty
    # ~/.oh-my-zsh would be treated as "installed" and the missing
    # oh-my-zsh.sh would then break every new zsh session).
    if [[ ! -f "$HOME/.oh-my-zsh/oh-my-zsh.sh" ]]; then
        if [[ "${ENVUP_DRY_RUN:-0}" == "1" ]]; then
            log_info "[dry-run] would install Oh-My-Zsh via official installer"
        else
            # If the directory exists but is broken / partial, the official
            # installer refuses to run. Move it out of the way first.
            if [[ -d "$HOME/.oh-my-zsh" ]]; then
                # shellcheck disable=SC2088  # literal ~ is display text, not a path to expand
                log_warn "~/.oh-my-zsh exists but is missing oh-my-zsh.sh; moving aside"
                mv "$HOME/.oh-my-zsh" "$HOME/.oh-my-zsh.envup-bak.$(date +%s)" || {
                    log_error "could not move broken ~/.oh-my-zsh aside"
                    return 1
                }
            fi
            log_step "Installing Oh-My-Zsh"
            # net_run_logged wraps the curl|sh in a timeout (default 300s,
            # override via ENVUP_NET_TIMEOUT_INSTALLER) AND redirects output
            # to the envup log — replaces the previous log_run-only call
            # which had no timeout protection and would hang forever on a
            # stalled GitHub fetch.
            local omz_url; omz_url="$(gh_url https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
            # shellcheck disable=SC2016  # $1 / $(...) are evaluated by the inner shells, not now
            net_run_logged "oh-my-zsh installer" -- bash -c \
                'sh -c "$(curl -fsSL "$1")" "" --unattended' _ "$omz_url" \
                || { log_error "Oh-My-Zsh install failed"; return 1; }
        fi
    fi

    # 3. Submodules for theme + plugins. submodule_ensure (lib.sh)
    # runs `git submodule update --init --recursive --quiet` and verifies
    # each plugin dir is non-empty; an empty dir = non-recursive clone +
    # failed update = silent breakage if we let the symlinks happen anyway.
    local -a plugin_dirs=()
    local p
    for p in "${PLUGINS[@]}"; do
        plugin_dirs+=("$ENVUP_HOME/modules/zsh/files/plugins/$p")
    done
    submodule_ensure zsh "${plugin_dirs[@]}" || return 1

    # 4. Symlinks
    log_step "Linking zsh configs"
    safe_link "modules/zsh/files/.zshenv"   "$HOME/.zshenv"  || return 1
    safe_link "modules/zsh/files/.zshrc"    "$HOME/.zshrc"   || return 1
    safe_link "modules/zsh/files/.zshrc.d"  "$HOME/.zshrc.d" || return 1
    safe_link "modules/zsh/files/.p10k.zsh" "$HOME/.p10k.zsh" || return 1
    safe_link "modules/zsh/files/.fzf.zsh"  "$HOME/.fzf.zsh"  || return 1

    # Plugins -> Oh-My-Zsh custom directory. Each ZSH_PLUGINS entry carries its
    # own omz-subdir (themes/ for the prompt theme, plugins/ for the rest), so
    # there's no name-based special-casing here. Add a plugin in meta.sh.
    local _entry plugin subdir
    for _entry in "${ZSH_PLUGINS[@]}"; do
        plugin="${_entry%%:*}"; subdir="${_entry##*:}"
        safe_link "modules/zsh/files/plugins/$plugin" \
            "$HOME/.oh-my-zsh/custom/$subdir/$plugin" || return 1
    done

    # 5. Expose envup itself on PATH so completion + invocation work from
    # anywhere. Done as part of the zsh module because (a) zsh users benefit
    # most and (b) zsh is always present in any non-trivial profile.
    if [[ -d "$HOME/.local/bin" || "${ENVUP_DRY_RUN:-0}" == "1" ]]; then
        safe_link "envup" "$HOME/.local/bin/envup" || return 1
    else
        mkdir -p "$HOME/.local/bin" && safe_link "envup" "$HOME/.local/bin/envup" || return 1
        log_hint "Make sure ~/.local/bin is on PATH (Ubuntu/Debian add it via ~/.profile)"
    fi
    # 6. Make zsh the shell you actually land in.
    _zsh_make_default

    log_success "zsh module installed."
    log_hint "Next steps:"
    log_hint "  1. Open a new terminal (or 'exec zsh') to load the new config"
    log_hint "  2. 'envup <Tab>' for completion (auto-loaded by tools.zsh)"
    log_hint "  3. Make sure ~/.local/bin is on PATH so 'envup' works from anywhere"
}

# Make zsh the default interactive shell. Two layers, because chsh alone is
# unreliable: on LDAP/SSSD-managed accounts (common on corp/HPC boxes) the
# passwd shell field isn't writable and chsh fails, so every new login lands
# in bash. The ~/.bashrc shim is the fallback that actually fixes those.
_zsh_make_default() {
    local zsh_path; zsh_path="$(command -v zsh)" || return 0

    # Layer 1: chsh (the "proper" way; effective on next login when it works).
    local current; current="$(getent passwd "$USER" 2>/dev/null | cut -d: -f7)"
    [[ -n "$current" ]] || current="$SHELL"
    if [[ "$current" == "$zsh_path" ]]; then
        log_info "zsh is already your login shell"
    elif [[ "${ENVUP_DRY_RUN:-0}" == 1 ]]; then
        log_info "[dry-run] would set login shell to zsh where possible (chsh)"
    elif [[ $EUID -eq 0 ]]; then
        # Only root can chsh without an interactive password prompt. Ensure zsh
        # is in /etc/shells first (chsh refuses an unlisted shell), and feed
        # chsh </dev/null so it can never block the install.
        grep -qxF "$zsh_path" /etc/shells 2>/dev/null || echo "$zsh_path" >>/etc/shells 2>/dev/null
        if chsh -s "$zsh_path" </dev/null >/dev/null 2>&1; then
            log_success "login shell changed to zsh (effective on next login)"
        else
            log_warn "chsh failed; the ~/.bashrc shim below will handle it"
        fi
    else
        # IMPORTANT: a non-root chsh prompts for a password (PAM), which would
        # HANG a non-interactive install. So we deliberately don't call it —
        # the ~/.bashrc shim below makes interactive bash enter zsh anyway.
        log_info "login shell left as-is (non-root chsh needs a password)"
        log_hint "to set it permanently yourself: chsh -s $zsh_path"
    fi

    # Layer 2: ~/.bashrc shim. Fires only for interactive bash that isn't
    # already zsh; NO_ZSH=1 is the escape hatch. Harmless no-op when chsh
    # already made zsh the login shell (bash never starts). Removed on
    # `envup uninstall zsh`.
    block_set "$HOME/.bashrc" zsh-default <<'SHIM'
# Drop interactive bash into zsh (covers logins where chsh can't change the
# shell, e.g. LDAP accounts). Escape with: NO_ZSH=1 bash
if [ -z "$ZSH_VERSION" ] && [ -t 1 ] && [ -z "$NO_ZSH" ] && command -v zsh >/dev/null 2>&1; then
    exec zsh
fi
SHIM
    log_info "bash->zsh shim installed in ~/.bashrc (escape: NO_ZSH=1 bash)"
}

_zsh_install
