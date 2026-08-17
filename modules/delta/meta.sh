#!/bin/bash
# shellcheck disable=SC2034  # every field here is read by lib/engine.sh
# Module: delta — a diff you can read.
#
# The git module has been ready for this since v0.2: modules/git/files/.gitconfig
# carries a [delta] section (inert while delta is absent), and `envup install
# git` writes the [pager] lines into ~/.gitconfig.envup only on machines where
# the binary actually exists. Until now nothing ever installed the binary, so
# that path was dead code on every machine. This is the other half.

NAME="delta"
DESCRIPTION="Syntax-highlighted git diffs with word-level changes"

# Not a hard requirement to install — delta is a standalone pager — but it has
# no purpose without git, and DEPENDS is also what guarantees git's config is
# on disk before hooks.sh goes to rewrite the generated part of it.
DEPENDS=(git)

VERIFY_BIN="delta"

PROVIDERS=(system github_release)
GH_REPO="dandavison/delta"

# The binary is delta; the package almost everywhere is git-delta, because
# `delta` as a package name was taken (by a Java library on Debian, by an
# unrelated tool elsewhere). Alpine is the exception and calls it delta, which
# is what PKG_DEFAULT falls back to.
PKG_NAMES=(debian:git-delta rhel:git-delta arch:git-delta brew:git-delta)

LINKS=()
CLEAN_PATHS=()
