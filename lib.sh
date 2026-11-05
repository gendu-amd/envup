#!/bin/bash
# Source helpers in dependency order; CLI, hooks, and tests enter here.
# Watchdog children source this loader too, reusing exported capabilities.

# Resolve our own directory rather than trusting $ENVUP_HOME: the CLI sets that
# *after* sourcing us, and tests source this file from an arbitrary cwd.
_ENVUP_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"

# shellcheck source=lib/log.sh
source "$_ENVUP_LIB/log.sh"
# shellcheck source=lib/caps.sh
source "$_ENVUP_LIB/caps.sh"
# log.sh cannot decide whether HOME is shared until caps.sh has inspected it.
# Scope machine-local state now, before any later library derives paths from it.
_envup_state_scope "$ENVUP_HOST" "$ENVUP_HOME_SHARED"
# shellcheck source=lib/fs.sh
source "$_ENVUP_LIB/fs.sh"
# shellcheck source=lib/clangd.sh
source "$_ENVUP_LIB/clangd.sh"
# shellcheck source=lib/net.sh
source "$_ENVUP_LIB/net.sh"
# shellcheck source=lib/pkg.sh
source "$_ENVUP_LIB/pkg.sh"
# shellcheck source=lib/manifest.sh
source "$_ENVUP_LIB/manifest.sh"
# shellcheck source=lib/module.sh
source "$_ENVUP_LIB/module.sh"
# shellcheck source=lib/verify.sh
source "$_ENVUP_LIB/verify.sh"
# shellcheck source=lib/engine.sh
source "$_ENVUP_LIB/engine.sh"

# Providers are interchangeable by design: each one is a single way of getting a
# tool onto the machine, and a module names the ones it can use in PROVIDERS.
# Loading the whole directory means adding a route is adding a file.
for _p in "$_ENVUP_LIB"/providers/*.sh; do
    # shellcheck source=/dev/null
    [[ -r "$_p" ]] && source "$_p"
done
unset _p

# The reporting half. It comes last because it reads the module contract through
# engine.sh and reports on the state the providers left behind.
# shellcheck source=lib/health.sh
source "$_ENVUP_LIB/health.sh"
# shellcheck source=lib/adopt.sh
source "$_ENVUP_LIB/adopt.sh"
# shellcheck source=lib/upgrade.sh
source "$_ENVUP_LIB/upgrade.sh"
# shellcheck source=lib/authoring.sh
source "$_ENVUP_LIB/authoring.sh"
# shellcheck source=lib/doctor.sh
source "$_ENVUP_LIB/doctor.sh"
