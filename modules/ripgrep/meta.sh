#!/bin/bash
# shellcheck disable=SC2034  # every field here is read by lib/engine.sh
# Fast recursive search used directly and by Telescope.

NAME="ripgrep"
DESCRIPTION="Fast recursive search — 'rg <pattern>', respects .gitignore"

DEPENDS=()

VERIFY_BIN="rg"

PROVIDERS=(system github_release)
GH_REPO="BurntSushi/ripgrep"

LINKS=()
CLEAN_PATHS=()
