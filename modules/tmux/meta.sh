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
# tmux before 3.1 has no --version, only -V: it prints a usage message and exits
# non-zero. envup reads that exit code as "this binary does not run here", so the
# flag has to be the one tmux actually answers on.
VERIFY_VERSION_ARG="-V"
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

# The committed per-machine layer, same idea as ~/.zshrc.d/hosts/. tmux cannot
# expand $(hostname) inside source-file, so envup resolves the hostname here and
# links this machine's file to one fixed path. '?' because most hosts have no
# file — that is the normal case, not a fault. Create one and re-run
# `envup install tmux` to pick it up.
LINKS+=("?modules/tmux/files/hosts/${ENVUP_HOST}.conf:$HOME/.tmux/host.conf")

# Not config: a helper the tmux binding and the shell both call. It rides with
# tmux because it is useless without it.
LINKS+=("modules/tmux/files/bin/tmux-sessionizer:$HOME/.local/bin/tmux-sessionizer")

# Deliberately empty. resurrect/continuum saves under
# ~/.local/share/tmux/resurrect/ are the layout you were last working in —
# user data, not cache. Delete that directory by hand if you really mean it.
CLEAN_PATHS=()
