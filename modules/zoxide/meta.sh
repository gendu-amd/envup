#!/bin/bash
# shellcheck disable=SC2034  # metadata fields are consumed by module_meta() via sourcing
# Module: zoxide
# Smarter `cd` — jump to frequently-used dirs with `z <pattern>`.

NAME="zoxide"
DESCRIPTION="Smarter cd — 'z <dir>' to jump, 'zi' to pick interactively"

# Shell integration (`eval "$(zoxide init zsh)"`) lives in the zsh module's
# tools.zsh, so zoxide is only useful alongside zsh.
DEPENDS=(zsh)

# Tools install.sh needs to be on PATH before it can run.
#   curl — the official installer fallback is curl-only.
SELF_DEPS=(curl)

# zoxide's frecency database (~/.local/share/zoxide) is user data, NOT cache —
# it's your accumulated directory history, so clean must never remove it.
CLEAN_PATHS=()
