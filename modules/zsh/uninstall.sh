#!/bin/bash
# zsh uninstall hook
# Removes envup-managed symlinks. Does NOT remove Oh-My-Zsh or the zsh package
# (the user may still want them).
#
# Plugin list comes from the shared ZSH_PLUGINS in meta.sh (same source
# install.sh uses), so adding a plugin can never leave a dangling symlink that
# uninstall forgets. `run_module_hook` cd's into the module dir first, so the
# relative source path is safe. Function-wrapped so `local` is legal (matches
# the install-hook discipline).
# shellcheck source=meta.sh
source ./meta.sh

_zsh_uninstall() {
    log_step "Removing zsh symlinks"
    unlink_safe "$HOME/.zshenv"
    unlink_safe "$HOME/.zshrc"
    unlink_safe "$HOME/.zshrc.d"
    unlink_safe "$HOME/.p10k.zsh"
    unlink_safe "$HOME/.fzf.zsh"

    local entry plugin subdir
    for entry in "${ZSH_PLUGINS[@]}"; do
        plugin="${entry%%:*}"; subdir="${entry##*:}"
        unlink_safe "$HOME/.oh-my-zsh/custom/$subdir/$plugin"
    done

    unlink_safe "$HOME/.local/bin/envup"

    # Remove the bash->zsh shim we appended to ~/.bashrc (no-op if absent).
    block_del "$HOME/.bashrc" zsh-default
    log_info "removed bash->zsh shim from ~/.bashrc (login shell via chsh is left as-is)"

    log_info "zsh package and Oh-My-Zsh kept (uninstall manually if desired)"
    log_info "Backups (if any): ${HOME}/.dotfiles_backup/"
}

_zsh_uninstall
