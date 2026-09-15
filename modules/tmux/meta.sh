#!/bin/bash
# shellcheck disable=SC2034  # every field here is read by lib/engine.sh
# tmux + vendored TPM plugins and session restore.

NAME="tmux"
DESCRIPTION="Terminal multiplexer with TPM + session restore"
DEPENDS=()

SELF_DEPS=(git)

VERIFY_BIN="tmux"
# Older tmux only supports -V.
VERIFY_VERSION_ARG="-V"
PROVIDERS=(system manual)
MANUAL_HINT="ask an admin for the 'tmux' package — envup will link ~/.tmux.conf regardless"

# Keep in sync with @plugin entries in files/.tmux.conf.
TMUX_PLUGINS=(tpm tmux-sensible tmux-resurrect tmux-continuum vim-tmux-navigator)

LINKS=("modules/tmux/files/.tmux.conf:$HOME/.tmux.conf")
for _p in "${TMUX_PLUGINS[@]}"; do
    LINKS+=("modules/tmux/files/plugins/$_p:$HOME/.tmux/plugins/$_p")
done
unset _p

# tmux cannot expand a hostname in source-file; envup links the selected file.
LINKS+=("?modules/tmux/files/hosts/${ENVUP_HOST}.conf:$HOME/.tmux/host.conf")

LINKS+=("modules/tmux/files/bin/tmux-sessionizer:$HOME/.local/bin/tmux-sessionizer")
LINKS+=("modules/tmux/files/bin/tmux-resume:$HOME/.local/bin/tmux-resume")

# Resurrect saves are user data, not cache.
CLEAN_PATHS=()
