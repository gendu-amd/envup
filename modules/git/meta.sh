#!/bin/bash
# shellcheck disable=SC2034  # every field here is read by lib/engine.sh
# Shared Git config; identity stays in ~/.gitconfig.local.

NAME="git"
DESCRIPTION="Git config (~/.gitconfig; delta as pager where it is installed)"
DEPENDS=()
SELF_DEPS=()

VERIFY_BIN="git"

PROVIDERS=(system manual)
MANUAL_HINT="ask an admin for the 'git' package — envup will link the config regardless"

LINKS=("modules/git/files/.gitconfig:$HOME/.gitconfig")

# Git cannot expand a hostname in an include, so envup links the selected file.
LINKS+=("?modules/git/files/hosts/${ENVUP_HOST}.gitconfig:$HOME/.gitconfig.host")

LINKS+=("modules/git/files/ignore:$HOME/.config/git/ignore")
CLEAN_PATHS=()
