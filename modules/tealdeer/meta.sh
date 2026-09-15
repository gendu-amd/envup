#!/bin/bash
# Module: tealdeer — fast, example-first command help through the `tldr` CLI.
# shellcheck disable=SC2034  # metadata is consumed by lib/engine.sh

NAME="tealdeer"
DESCRIPTION="Fast practical command examples — 'tldr <command>'"
DEPENDS=()

VERIFY_BIN="tldr"
PROVIDERS=(system github_release)
GH_REPO="tealdeer-rs/tealdeer"

LINKS=()
CLEAN_PATHS=("${XDG_CACHE_HOME:-$HOME/.cache}/tealdeer")
