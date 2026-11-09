#!/bin/bash
# Module: yazi — Vim-style terminal file manager with async previews.
# shellcheck disable=SC2034  # metadata is consumed by lib/engine.sh

NAME="yazi"
DESCRIPTION="Fast terminal file manager — run 'y' to keep its final directory"
DEPENDS=()

VERIFY_BIN="yazi"
PROVIDERS=(system github_release)
GH_REPO="sxyazi/yazi"
GH_BINS=(yazi ya)
# Current GNU builds require a newer glibc than several supported servers.
# The musl archive is static and runs on both musl and glibc Linux hosts.
GH_ASSET_AVOID=(unknown-linux-gnu)

LINKS=()
CLEAN_PATHS=()
