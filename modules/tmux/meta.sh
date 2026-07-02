#!/bin/bash
# shellcheck disable=SC2034  # metadata fields are consumed by module_meta() via sourcing
# Module: tmux — TPM + session restore. Symlinks ~/.tmux.conf and plugins into
# ~/.tmux/plugins/.
NAME="tmux"
DESCRIPTION="Terminal multiplexer with TPM + session restore"
DEPENDS=()

# Tools install.sh needs to be on PATH before it can run.
#   git — for `git submodule update --init` to fetch TPM + tmux plugins
#         when the user clone'd without --recursive.
SELF_DEPS=(git)

# `envup clean tmux` is a no-op by design. Resurrect/continuum session
# saves under ~/.local/share/tmux/resurrect/ are USER DATA (last layout
# you were working in), not cache — destroying them defeats the point of
# having session restore. If you really want a clean slate, delete that
# directory by hand.
CLEAN_PATHS=()

# Single source of truth for "what tmux plugins ship with this module" —
# used by install.sh's submodule verify + symlink loop and uninstall.sh's
# unlink loop. Defined here (in meta.sh) rather than in install.sh because
# both install.sh and uninstall.sh are sourced into hook subshells that
# already source meta.sh, so this is the only place visible to both.
#
# IMPORTANT: keep this in sync with the `set -g @plugin '...'` lines in
# `modules/tmux/files/.tmux.conf`. The conf file is intentionally NOT
# templated from this array — it's user-facing config, expected to be
# editable + grep-able by humans, and the bash machinery to render it
# would cost more than the once-in-a-blue-moon manual sync. When you
# add/remove a plugin: edit BOTH this array AND .tmux.conf.
TMUX_PLUGINS=(tpm tmux-sensible tmux-resurrect tmux-continuum vim-tmux-navigator)
