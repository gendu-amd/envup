#!/bin/bash
# shellcheck disable=SC2034  # every field here is read by lib/engine.sh
# Per-directory environment, integrated by zsh's tool slice.

NAME="direnv"
DESCRIPTION="Per-directory environment — .envrc loaded on cd, unloaded on leave"

DEPENDS=(zsh)

VERIFY_BIN="direnv"

PROVIDERS=(system github_release)
GH_REPO="direnv/direnv"

LINKS=()

# The .envrc allow-list is user security state, not cache.
CLEAN_PATHS=()
