#!/bin/bash
# shellcheck disable=SC2034  # metadata fields are consumed by module_meta() via sourcing
# Module: atuin
# SQLite-backed shell history with fuzzy search and optional sync.

NAME="atuin"
DESCRIPTION="Better shell history (Ctrl+R) with SQLite + fuzzy search"
DEPENDS=(zsh)

# Tools install.sh needs to be on PATH before it can run.
#   curl  — the official `setup.atuin.sh` installer is curl-only.
SELF_DEPS=(curl)

# Paths `envup clean atuin` may remove. atuin's SQLite DB is user data,
# NOT cache, so we don't list it here — clean must never destroy history.
CLEAN_PATHS=()
