#!/bin/bash
# shellcheck disable=SC2034  # every field here is read by lib/engine.sh
# Module: direnv — per-directory environment, loaded on cd.
#
# modules/zsh/files/.zshrc.d/50-tools.zsh has run `eval "$(direnv hook zsh)"`
# whenever the binary exists since 0.2.0; nothing installed the binary, so the
# hook has never fired on a machine envup set up.
#
# It is the answer to the thing that actually goes wrong on a shared server:
# per-project PATH, CUDA/ROCm prefixes, API keys and virtualenvs, all set by
# hand in a login shell and then leaking into every other project in the same
# session. direnv scopes them to the directory and unsets them on the way out.

NAME="direnv"
DESCRIPTION="Per-directory environment — .envrc loaded on cd, unloaded on leave"

# The `cd` hook lives in the zsh module's tools slice. Without it direnv is
# installed and silent — it only ever runs from a shell hook.
DEPENDS=(zsh)

VERIFY_BIN="direnv"

PROVIDERS=(system github_release)
GH_REPO="direnv/direnv"

# The release assets are bare binaries named direnv.<os>-<arch> — no archive,
# which the provider handles (it chmods and renames). One Go binary, no libc
# variants to choose between, so a machine with a glibc too old for the Rust
# tools still gets this one.

# Called direnv by apt, dnf, pacman, apk and brew alike.

LINKS=()

# ~/.local/share/direnv holds the allow-list: which .envrc files you have
# explicitly trusted. That is a security decision you made, not a cache, so
# clean must never remove it — losing it silently re-blocks every project.
CLEAN_PATHS=()
