#!/bin/bash
# shellcheck disable=SC2034  # every field here is read by lib/engine.sh
# Syntax-highlighted cat. Debian names the binary batcat; hooks.sh adds a shim.

NAME="bat"
DESCRIPTION="cat with syntax highlighting — 'bat <file>'"

DEPENDS=()

VERIFY_BIN="bat"

PROVIDERS=(system github_release)
GH_REPO="sharkdp/bat"

LINKS=()
CLEAN_PATHS=()
