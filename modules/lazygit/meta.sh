#!/bin/bash
# Module: lazygit — terminal UI for day-to-day Git operations.
# shellcheck disable=SC2034  # metadata is consumed by lib/engine.sh

NAME="lazygit"
DESCRIPTION="Terminal UI for staging, history, branches and rebases"
DEPENDS=(git)

VERIFY_BIN="lazygit"
PROVIDERS=(system github_release)
GH_REPO="jesseduffield/lazygit"
PKG_NAMES=(debian:- rhel:-)

LINKS=()
CLEAN_PATHS=()
