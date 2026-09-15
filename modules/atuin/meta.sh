#!/bin/bash
# shellcheck disable=SC2034  # every field here is read by lib/engine.sh
# Module: atuin — SQLite-backed shell history with fuzzy search.
# The Ctrl+R hook is wired up by the zsh module's tools slice.

NAME="atuin"
DESCRIPTION="Better shell history (Ctrl+R) with SQLite + fuzzy search"
DEPENDS=(zsh)

VERIFY_BIN="atuin"

# github_release before script deliberately: setup.atuin.sh downloads a release
# tarball anyway, but does it with its own curl, so a mirror or a proxy that
# only envup knows about never reaches it. Going through the provider keeps
# every byte on the route lib/net.sh decides.
PROVIDERS=(system github_release script)
GH_REPO="atuinsh/atuin"
SCRIPT_URL="https://setup.atuin.sh"

# atuin only reached apt in Ubuntu 24.04 / Debian trixie. Naming it anyway is
# right: pkg_install failing here just moves the chain along, and machines new
# enough to have it should use it.
PKG_NAMES=()

# Escape hatch kept from v0.1: atuin is nice-to-have and its installer was
# historically the step most likely to hang on a blocked network.
# shellcheck disable=SC2016  # evaluated by the engine at install time, not now
APPLIES_IF='[[ "${ENVUP_ATUIN_INSTALL:-}" != skip ]]'

LINKS=()

# The SQLite DB under ~/.local/share/atuin is user data — years of shell
# history — not cache. clean must never be able to remove it.
CLEAN_PATHS=()
