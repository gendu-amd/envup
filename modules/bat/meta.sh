#!/bin/bash
# shellcheck disable=SC2034  # every field here is read by lib/engine.sh
# Module: bat — cat with syntax highlighting and a pager that knows when to stay
# out of the way.
#
# Like eza, the alias slice already reaches for it: 60-alias.zsh points `cat` at
# `bat --style=plain` when it exists. It is also what makes fzf's preview window
# worth having on a config file.
#
# The name is the complication, the same way it is for fd — see hooks.sh.

NAME="bat"
DESCRIPTION="cat with syntax highlighting — 'bat <file>'"

DEPENDS=()

VERIFY_BIN="bat"

PROVIDERS=(system github_release)
GH_REPO="sharkdp/bat"

# The *package* is called bat everywhere, including Debian — it is the binary
# inside it that Debian renames, so there is nothing for PKG_NAMES to fix. The
# release assets are named bat-v<version>-<triple>, gnu and musl both, and they
# carry the syntax and theme sets with them.

LINKS=()
CLEAN_PATHS=()
