#!/bin/bash
# ============================================
# envup shared library — the loader.
# ============================================
# Sourcing this file is the only supported way in. It pulls in lib/*.sh in
# dependency order so that nothing else — not the CLI, not a module hook, not a
# test — has to know what that order is.
#
#   log       logging + verbosity gate                     (nothing)
#   caps      OS / distro / arch / libc / privilege /       (log)
#             host / shared-home / network — what we CAN do
#   fs        path resolution, symlinks, managed blocks     (log)
#   net       mirror rewriting, timeouts, fetch, clone      (log, caps)
#   pkg       package managers                              (log, caps, net)
#   manifest  which modules are installed on this machine   (log)
#   module    meta / deps / profiles / hook runner          (log, caps, net)
#   engine    the declarative install driver                (all of the above)
#   providers one route each to getting a tool installed    (engine)
#   health    what is actually true on this machine now     (fs, manifest, engine)
#   adopt     rescuing third-party edits out of the repo    (health)
#   authoring static checks of the module contract          (module)
#   doctor    diagnose + repair, on top of all three        (health, adopt, authoring)
#
# Later files may use earlier ones, never the reverse. Each documents its own
# contract at the top; to add one, create lib/<name>.sh and source it below at
# the point where its dependencies are already loaded.
#
# This file is also re-sourced by the fresh bash that run_module_hook spawns per
# hook, which is how a hook gets every helper back (functions and arrays cannot
# be exported). Detection results are exported and re-used rather than re-probed
# — see lib/caps.sh.
# ============================================

# Resolve our own directory rather than trusting $ENVUP_HOME: the CLI sets that
# *after* sourcing us, and tests source this file from an arbitrary cwd.
_ENVUP_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"

# shellcheck source=lib/log.sh
source "$_ENVUP_LIB/log.sh"
# shellcheck source=lib/caps.sh
source "$_ENVUP_LIB/caps.sh"
# shellcheck source=lib/fs.sh
source "$_ENVUP_LIB/fs.sh"
# shellcheck source=lib/net.sh
source "$_ENVUP_LIB/net.sh"
# shellcheck source=lib/pkg.sh
source "$_ENVUP_LIB/pkg.sh"
# shellcheck source=lib/manifest.sh
source "$_ENVUP_LIB/manifest.sh"
# shellcheck source=lib/module.sh
source "$_ENVUP_LIB/module.sh"
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
# shellcheck source=lib/authoring.sh
source "$_ENVUP_LIB/authoring.sh"
# shellcheck source=lib/doctor.sh
source "$_ENVUP_LIB/doctor.sh"
