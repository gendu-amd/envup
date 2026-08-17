#!/bin/bash
# shellcheck disable=SC2034  # every field here is read by lib/engine.sh
# Module: fd — find, without the argument syntax.
#
# fzf uses it as FZF_DEFAULT_COMMAND when it is present (see the zsh module's
# 50-tools slice): Ctrl-T then lists the files git would track instead of
# walking .git/ and node_modules/, which on a big repo is the difference between
# instant and useless.
#
# The name is the whole complication — see hooks.sh.

NAME="fd"
DESCRIPTION="Friendlier find — 'fd <pattern>', respects .gitignore"

DEPENDS=()

VERIFY_BIN="fd"

PROVIDERS=(system github_release)
GH_REPO="sharkdp/fd"

# Debian shipped a different `fd` long before this one existed, so its package
# is fd-find — and so is Fedora's, which followed Debian. Arch, brew and Alpine
# all just call it fd, which is what PKG_DEFAULT falls back to.
PKG_NAMES=(debian:fd-find rhel:fd-find)

LINKS=()
CLEAN_PATHS=()
