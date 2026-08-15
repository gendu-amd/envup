#!/bin/bash
# ============================================
# envup — modules, profiles, and running module hooks
# ============================================
# A module is a directory under modules/<name>/ described by meta.sh; a profile
# is profiles/<name>.sh declaring MODULES=(...). This file reads both, works out
# the install order, and runs the hooks.
#
# Depends on: log.sh, caps.sh, net.sh
# ============================================

modules_available() { local d; for d in "$ENVUP_HOME"/modules/*/; do [[ -d "$d" ]] && basename "$d"; done; }
module_exists()     { [[ -d "$ENVUP_HOME/modules/$1" ]]; }

# Read a meta.sh field (scalar or array) — one value per line. Empty if unset.
module_meta() {
    local meta="$ENVUP_HOME/modules/$1/meta.sh"
    [[ -f "$meta" ]] || return 0
    ( set +u; source "$meta"; local ref="$2[@]"; printf '%s\n' "${!ref}" ) 2>/dev/null
}
module_deps() { local d; module_meta "$1" DEPENDS | while IFS= read -r d; do [[ -n "$d" ]] && echo "$d"; done; }

# Resolve install order: each module's DEPENDS come before it; deduped.
resolve_order() {
    local -A seen=(); local -a out=()
    _visit() {
        local m="$1" d
        [[ -n "${seen[$m]:-}" ]] && return 0
        seen[$m]=1
        for d in $(module_deps "$m"); do module_exists "$d" && _visit "$d"; done
        out+=("$m")
    }
    local m; for m in "$@"; do module_exists "$m" && _visit "$m"; done
    (( ${#out[@]} )) && printf '%s\n' "${out[@]}"
    return 0
}

profiles_available() { local f; for f in "$ENVUP_HOME"/profiles/*.sh; do [[ -f "$f" ]] && basename "$f" .sh; done; }

# use_profile <name> — include another profile's modules into MODULES. Called
# from within a profile file to compose profiles (e.g. full = standard + nvim)
# instead of restating the whole list. Profiles append with `MODULES+=(...)`,
# so composition chains cleanly; resolve_order dedups the result.
use_profile() {
    local f="$ENVUP_HOME/profiles/$1.sh"
    [[ -f "$f" ]] || { log_error "unknown base profile: $1"; return 1; }
    source "$f"
}

# load_profile <name> -> populates the global MODULES array.
load_profile() {
    local f="$ENVUP_HOME/profiles/$1.sh"
    [[ -f "$f" ]] || { log_error "unknown profile: $1"; log_hint "available: $(profiles_available | tr '\n' ' ')"; return 1; }
    MODULES=(); source "$f"
    (( ${#MODULES[@]} )) || { log_error "profile '$1' defines no MODULES"; return 1; }
}

# run_module_hook <module> <install|uninstall> — drive one module through the
# engine, in its own process.
#
# Isolation, because a module is data plus optional hook functions and both get
# sourced: meta.sh from module A must not still be defining PROVIDERS when
# module B is processed. (_engine_load resets the fields it knows about; a fresh
# process is what covers the ones it doesn't.)
#
# Watchdog, because no single module may wedge the whole sequential run —
# whatever it does inside (a stuck package manager, a forgotten net_run, a step
# reading stdin). On timeout the module is reported failed and the run moves on.
#
# The child is a fresh bash and re-sources lib.sh to get every helper back
# (functions and arrays cannot be exported); $HOME, $ENVUP_HOME, $ENVUP_LOG_FILE
# and the detected capabilities are already exported.
#
# Returns the engine's result code: 0 ok, 70 degraded, 71 skipped, else failed.
run_module_hook() {
    local mod="$1" action="$2" dir="$ENVUP_HOME/modules/$1"
    [[ -f "$dir/meta.sh" ]] || { log_error "[$mod] no meta.sh — not a module"; return 1; }
    case "$action" in install|uninstall) ;; *) log_error "unknown action: $action"; return 1 ;; esac
    log_step "[$mod] $action"

    local t; t=$(timeout_bin)
    if [[ -z "$t" ]]; then
        log_once no_timeout log_warn "no 'timeout' binary — module hooks run without a watchdog (macOS: brew install coreutils)"
        ( cd "$dir" && "engine_$action" "$mod" )
        return $?
    fi

    # "$BASH", not bash: on macOS the CLI has already re-exec'd itself into
    # Homebrew's bash 5 because /bin/bash is the 3.2 Apple ships, and spawning a
    # bare `bash` here would drop the child back to 3.2 — where lib.sh's
    # associative arrays and ${var^^} are syntax errors. Falls back to the PATH
    # lookup only if $BASH is somehow unset.
    # shellcheck disable=SC2016  # the positional args expand inside the child bash, not now
    "$t" -k "$ENVUP_NET_KILL_AFTER" "$ENVUP_MODULE_TIMEOUT" \
        "${BASH:-bash}" -c 'set -uo pipefail; source "$ENVUP_HOME/lib.sh"; cd "$1" || exit 1; "engine_$2" "$3"' \
        _ "$dir" "$action" "$mod"
    local rc=$?
    if (( rc == 124 || rc == 137 || rc == 143 )); then
        log_error "[$mod] $action timed out after ${ENVUP_MODULE_TIMEOUT}s and was killed"
        log_hint "raise it: ENVUP_MODULE_TIMEOUT=1800 envup install $mod"
    fi
    return $rc
}
