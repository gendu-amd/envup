#!/bin/bash
# git uninstall hook — remove the shared .gitconfig symlink. Keeps
# ~/.gitconfig.local (your identity) strictly untouched. Function-wrapped per
# the module-hook discipline so a future `local` can't break it.
_git_uninstall() {
    unlink_safe "$HOME/.gitconfig"
    # shellcheck disable=SC2088  # literal ~ is display text, not a path to expand
    log_info "~/.gitconfig.local (your identity) kept"
}
_git_uninstall
