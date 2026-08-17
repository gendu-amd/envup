#!/bin/bash
# shellcheck disable=SC2034  # every field here is read by lib/engine.sh
# Module: eza — the `ls` the alias slice has been waiting for.
#
# modules/zsh/files/.zshrc.d/60-alias.zsh has pointed ls/ll/la/tree at eza since
# 0.2.0, guarded by `(( $+commands[eza] ))`. Nothing ever installed it, so on
# every machine the guard was false and you got plain `ls` — which is fine, and
# is exactly why nobody noticed the feature was never turning on.

NAME="eza"
DESCRIPTION="A modern ls — colours, icons, git status, --tree"

DEPENDS=()

VERIFY_BIN="eza"

PROVIDERS=(system github_release)
GH_REPO="eza-community/eza"

# The upstream release is Linux and Windows only — there is no darwin asset, on
# purpose (they point Mac users at brew). So on macOS this module lives or dies
# by the system provider, and `brew install eza` is the whole story. Everywhere
# else the release covers it, root or no root.

# eza also publishes a *_no_libgit build of every platform: the same program
# with git support compiled out. `ll` is `eza -la --git`, so picking that one
# would give a column of dashes where the git status should be, on a binary
# whose --version looks completely normal. See GH_ASSET_AVOID in the provider.
GH_ASSET_AVOID=(no_libgit)

# Named eza on apt (Ubuntu 24.04+, Debian 13+), dnf, pacman, apk and brew
# alike. Older Debian and RHEL have no package at all, which is not something
# PKG_NAMES can express — the system provider fails, and github_release, which
# is next in the list, is the one that was going to work there anyway.

LINKS=()
CLEAN_PATHS=()
