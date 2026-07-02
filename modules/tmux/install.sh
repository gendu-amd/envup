#!/bin/bash
# tmux install hook
#
# Steps:
#   1. Install tmux package via system pkg manager
#   2. Initialize git submodules for TPM + tmux plugins (submodule_ensure in
#      lib.sh verifies each plugin dir is non-empty)
#   3. Symlink .tmux.conf into ~/
#   4. Symlink each plugin into ~/.tmux/plugins/<name>
#
# IMPORTANT: the whole hook body is wrapped in `_tmux_install()` so that
# `local` is legal at every step (same pattern as atuin/nvim/zsh/git/fzf).
# Module hooks are sourced into a subshell by `run_module_hook`, but the
# subshell is NOT a function context, so `local` at the top level fails with
#     local: can only be used in a function
#
# safe_link always backs up a pre-existing real file at the target into
# ~/.dotfiles_backup/<ts>/ before linking — no per-call handling needed here.
#
# `TMUX_PLUGINS` (the single source of truth for shipped plugin names) lives
# in `meta.sh` — see the comment there for why. We `source ./meta.sh` here
# so install.sh + uninstall.sh share the same list. `run_module_hook` cd's
# into the module dir before sourcing this script, so the relative path is
# safe.
# shellcheck source=meta.sh
source ./meta.sh

_tmux_install() {
    # 1. system package
    if ! pkg_have tmux; then
        pkg_install tmux || return 1
    fi

    # 2. Submodules for TPM + plugins. submodule_ensure (lib.sh)
    # runs `git submodule update --init --recursive --quiet` and verifies
    # each plugin dir is non-empty; an empty dir = non-recursive clone +
    # failed update = silent breakage.
    local -a plugin_dirs=()
    local p
    for p in "${TMUX_PLUGINS[@]}"; do
        plugin_dirs+=("$ENVUP_HOME/modules/tmux/files/plugins/$p")
    done
    submodule_ensure tmux "${plugin_dirs[@]}" || return 1

    # 3. Config
    log_step "Linking tmux configs"
    safe_link "modules/tmux/files/.tmux.conf" "$HOME/.tmux.conf" || return 1

    # 4. Plugins -> ~/.tmux/plugins/<name>
    # safe_link auto-backs-up any existing real directory at the destination
    # (e.g. plugins previously cloned manually by TPM via `prefix + I`).
    local plugin
    for plugin in "${TMUX_PLUGINS[@]}"; do
        safe_link "modules/tmux/files/plugins/$plugin" "$HOME/.tmux/plugins/$plugin" || return 1
    done

    log_success "tmux module installed."
    log_hint "Next steps:"
    log_hint "  1. Reload config:   tmux source ~/.tmux.conf  (or restart tmux)"
    log_hint "  2. New tmux server will auto-restore the last saved session"
    log_hint "  3. Manual save / restore inside tmux: prefix Ctrl-s / prefix Ctrl-r"
    log_hint "  4. Per-machine overrides go in ~/.tmux.local (gitignored, optional)"
}

_tmux_install
