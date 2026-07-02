#!/bin/bash
# shellcheck disable=SC2034  # metadata fields are consumed by module_meta() via sourcing
# Module: git — shared ~/.gitconfig (symlinked); personal identity stays in
# ~/.gitconfig.local, which uninstall keeps.
NAME="git"
DESCRIPTION="Git config (~/.gitconfig with delta as pager)"
DEPENDS=()

# Tools install.sh needs to be on PATH before it can run.
# (git is bootstrapped via pkg_install inside install.sh itself if missing,
#  so we don't need to declare it here.)
SELF_DEPS=()

# `envup clean git` does nothing — config is the user's source of truth,
# not cache. Identity lives in ~/.gitconfig.local which uninstall keeps.
CLEAN_PATHS=()
