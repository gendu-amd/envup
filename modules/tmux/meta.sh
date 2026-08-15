#!/bin/bash
# shellcheck disable=SC2034  # every field here is read by lib/engine.sh
# Module: tmux — TPM + session restore.

NAME="tmux"
DESCRIPTION="Terminal multiplexer with TPM + session restore"
DEPENDS=()

# `git submodule update --init` fetches TPM and the plugins for anyone who
# cloned without --recursive.
SELF_DEPS=(git)

VERIFY_BIN="tmux"
# Like git: compiling tmux (and libevent, and ncurses) on a server you do not
# own is not something envup should attempt. Package manager or a sentence.
PROVIDERS=(system manual)
MANUAL_HINT="ask an admin for the 'tmux' package — envup will link ~/.tmux.conf regardless"

# The plugins this module ships. Keep in sync with the `set -g @plugin '...'`
# lines in files/.tmux.conf — the conf is user-facing config meant to be read
# and edited by hand, so it is deliberately not generated from this array.
TMUX_PLUGINS=(tpm tmux-sensible tmux-resurrect tmux-continuum vim-tmux-navigator)

LINKS=("modules/tmux/files/.tmux.conf:$HOME/.tmux.conf")
for _p in "${TMUX_PLUGINS[@]}"; do
    LINKS+=("modules/tmux/files/plugins/$_p:$HOME/.tmux/plugins/$_p")
done
unset _p

# Deliberately empty. resurrect/continuum saves under
# ~/.local/share/tmux/resurrect/ are the layout you were last working in —
# user data, not cache. Delete that directory by hand if you really mean it.
CLEAN_PATHS=()
