#!/bin/bash
# shellcheck disable=SC2034  # every field here is read by lib/engine.sh
# Modern ls, enabled by zsh aliases when present.

NAME="eza"
DESCRIPTION="A modern ls — colours, icons, git status, --tree"

DEPENDS=()

VERIFY_BIN="eza"

PROVIDERS=(system github_release)
GH_REPO="eza-community/eza"

# Avoid upstream builds without the Git support used by `ll`.
GH_ASSET_AVOID=(no_libgit)

LINKS=()
CLEAN_PATHS=()
