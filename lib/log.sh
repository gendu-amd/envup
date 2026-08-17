#!/bin/bash
# ============================================
# envup — logging + the two smallest primitives everything else needs
# ============================================
# Two independent sinks:
#   terminal   gated by ENVUP_LOG_LEVEL (debug < info < warn < error)
#   log file   ENVUP_LOG_FILE, which always records every level
# so raising the terminal threshold never costs you the record of what happened.
#
# No dependencies. This file is sourced first.
# ============================================

if [[ -t 1 ]]; then
    C_RED=$'\033[0;31m'; C_GRN=$'\033[0;32m'; C_YEL=$'\033[1;33m'
    C_BLU=$'\033[0;34m'; C_CYN=$'\033[0;36m'; C_BLD=$'\033[1m'; C_NC=$'\033[0m'
else
    C_RED='' C_GRN='' C_YEL='' C_BLU='' C_CYN='' C_BLD='' C_NC=''
fi
ENVUP_LOG_FILE="${ENVUP_LOG_FILE:-/dev/null}"
_logf() { ( printf '[%s] [%s] %s\n' "$(date '+%F %T')" "$1" "$2" >>"$ENVUP_LOG_FILE" ) 2>/dev/null || true; }

# Terminal verbosity gate. ENVUP_LOG_LEVEL in {debug,info,warn,error} (default
# info) filters what reaches the terminal; the log file always records every
# level via _logf. `_should_log <level>` is true when <level> is at or above the
# configured threshold.
_lvl_num() { case "$1" in debug) echo 0 ;; info) echo 1 ;; warn) echo 2 ;; error) echo 3 ;; *) echo 1 ;; esac; }
_should_log() { (( $(_lvl_num "$1") >= $(_lvl_num "${ENVUP_LOG_LEVEL:-info}") )); }

log_step()    { _should_log info  && printf '\n%s==>%s %s%s%s\n' "$C_BLU" "$C_NC" "$C_BLD" "$*" "$C_NC"; _logf STEP "$*"; }
log_info()    { _should_log info  && printf '%s[i]%s %s\n' "$C_CYN" "$C_NC" "$*"; _logf INFO "$*"; }
log_success() { _should_log info  && printf '%s✓%s %s\n' "$C_GRN" "$C_NC" "$*"; _logf OK "$*"; }
log_warn()    { _should_log warn  && printf '%s⚠%s %s\n' "$C_YEL" "$C_NC" "$*" >&2; _logf WARN "$*"; }
log_error()   { _should_log error && printf '%s✗%s %s\n' "$C_RED" "$C_NC" "$*" >&2; _logf ERROR "$*"; }
log_hint()    { _should_log info  && printf '  %s→%s %s\n' "$C_YEL" "$C_NC" "$*" >&2; _logf HINT "$*"; }
log_debug()   { _should_log debug && printf '%s[d]%s %s\n' "$C_CYN" "$C_NC" "$*" >&2; _logf DEBUG "$*"; }

# log_once <key> <log_fn> <message>... — emit a message at most once per run.
# The "once" is remembered in an exported variable, so it also holds across the
# hook subshells run_module_hook spawns (each of them re-sources this library).
log_once() {
    local key="_ENVUP_SAID_${1//[^A-Za-z0-9_]/_}" fn="$2"; shift 2
    [[ -n "${!key:-}" ]] && return 0
    printf -v "$key" 1; export "${key?}"
    "$fn" "$@"
}

have() { command -v "$1" &>/dev/null; }

# ---- where per-machine state lives ---------------------------------------
# One definition, used by the manifest, the created-file ledger, adopt's
# stash and the command logs. It lives in the first-sourced file only because
# lib/fs.sh needs it before lib/manifest.sh (which is its real owner) loads.
#
# XDG_STATE_HOME is honoured, but never at the cost of losing state that is
# already on disk: a machine that has been using the historical path keeps
# using it, so setting the variable later can't make an installed environment
# look uninstalled.
_envup_state_default() {
    local legacy="$HOME/.local/state/envup"
    if [[ -n "${XDG_STATE_HOME:-}" && ! -d "$legacy" ]]
    then printf '%s/envup' "${XDG_STATE_HOME%/}"
    else printf '%s' "$legacy"; fi
}
ENVUP_STATE_DIR="${ENVUP_STATE_DIR:-$(_envup_state_default)}"
ENVUP_LOG_DIR="${ENVUP_LOG_DIR:-$ENVUP_STATE_DIR/logs}"

# One timestamped log file per command (reused if already open).
log_init() {
    [[ "${ENVUP_LOG_FILE:-/dev/null}" != /dev/null ]] && return 0
    mkdir -p "$ENVUP_LOG_DIR"
    ENVUP_LOG_FILE="$ENVUP_LOG_DIR/$1_$(date +%Y%m%d_%H%M%S).log"; export ENVUP_LOG_FILE
    log_info "log: $ENVUP_LOG_FILE"
}
