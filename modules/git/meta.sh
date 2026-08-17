#!/bin/bash
# shellcheck disable=SC2034  # every field here is read by lib/engine.sh
# Module: git — the shared ~/.gitconfig. It carries no [user] section and ends
# with `[include] ~/.gitconfig.local`, so identity stays off the repo.

NAME="git"
DESCRIPTION="Git config (~/.gitconfig; delta as pager where it is installed)"
DEPENDS=()
SELF_DEPS=()

VERIFY_BIN="git"

# There is no honest user-space route for git: it needs compiling, and nobody
# should be downloading a git binary from a release page to a server they do
# not administer. So the chain is the package manager, then a sentence for a
# human — which leaves the module 'degraded', config linked, working the day an
# admin installs the package.
PROVIDERS=(system manual)
MANUAL_HINT="ask an admin for the 'git' package — envup will link the config regardless"

LINKS=("modules/git/files/.gitconfig:$HOME/.gitconfig")

# The committed per-machine layer, same idea as ~/.zshrc.d/hosts/. git's
# [include] takes a fixed path and has no hostname condition, so envup resolves
# the name here and links this machine's file to one place. '?' because most
# hosts have no file — the normal case. Create one and re-run
# `envup install git` to pick it up.
LINKS+=("?modules/git/files/hosts/${ENVUP_HOST}.gitconfig:$HOME/.gitconfig.host")

# Config is the user's source of truth, never cache.
CLEAN_PATHS=()
