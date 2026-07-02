#!/bin/bash
# shellcheck disable=SC2034  # metadata fields are consumed by module_meta() via sourcing
# Module: fzf — fuzzy finder. Installs the binary; no config symlinks (key
# bindings load via the zsh module's .fzf.zsh).
NAME="fzf"
DESCRIPTION="Fuzzy finder (Ctrl+T files, Ctrl+R history fallback)"
DEPENDS=()

# Tools install.sh needs to be on PATH before it can run.
#   git  — official installer is a git clone (on apt/dnf/yum/apk distros;
#          brew/pacman go through the system package manager instead).
#   curl — handy for follow-up downloads; we keep it small.
SELF_DEPS=(git)

# fzf install is either ~/.fzf (git clone, owner-marker tracked by install.sh
# so uninstall is safe) or a system package — nothing here qualifies as
# "cache that can be safely nuked". The install/uninstall pair handles
# its own filesystem state.
CLEAN_PATHS=()
