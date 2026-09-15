#!/bin/bash
# shellcheck disable=SC2034  # every field here is read by lib/engine.sh
# Friendly find used by fzf. Debian/Fedora name the binary fdfind.

NAME="fd"
DESCRIPTION="Friendlier find — 'fd <pattern>', respects .gitignore"

DEPENDS=()

VERIFY_BIN="fd"

PROVIDERS=(system github_release)
GH_REPO="sharkdp/fd"

PKG_NAMES=(debian:fd-find rhel:fd-find)

LINKS=()
CLEAN_PATHS=()
