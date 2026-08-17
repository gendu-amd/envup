#!/bin/bash
# shellcheck disable=SC2034  # every field here is read by lib/engine.sh
# Module: ripgrep — the grep the rest of the setup assumes.
#
# It is a dependency in practice long before anyone installs it on purpose:
# Telescope's live_grep (<leader>fw in NvChad) shells out to rg and quietly does
# nothing without it, and `rg` is what makes searching a large tree over SSH
# finish while you are still looking at the screen. One static binary, so the
# no-root route works.

NAME="ripgrep"
DESCRIPTION="Fast recursive search — 'rg <pattern>', respects .gitignore"

# Useful entirely on its own, at a shell that envup did not install.
DEPENDS=()

# The package is ripgrep; the binary is rg. This is the one the engine checks,
# because a package that installed and a command you can run are not the same
# claim (see bin_runs in lib/engine.sh).
VERIFY_BIN="rg"

PROVIDERS=(system github_release)
GH_REPO="BurntSushi/ripgrep"

# Called ripgrep on apt, dnf, pacman, brew and apk alike — the rare tool that
# needs no PKG_NAMES table.

LINKS=()
CLEAN_PATHS=()
