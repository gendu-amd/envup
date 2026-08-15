#!/bin/bash
# ============================================
# envup — the way out to the network
# ============================================
# Everything that leaves this machine goes through here. That is the whole point
# of the file: a mirror prefix, a proxy or an offline run has to be honoured by
# *every* download, and the only way to guarantee that is to have one door. A
# module that reaches for curl directly is a module the mirror silently doesn't
# apply to (which is exactly how the atuin installer used to escape it).
#
# Every call is also time-boxed. A stuck mirror is far more common than a
# genuinely slow one, and an install that hangs forever is worse than one that
# fails in two minutes with a reason.
#
# Depends on: log.sh, caps.sh
# ============================================

# gh_url <url> — rewrite a GitHub URL through a mirror/proxy when ENVUP_GH_MIRROR
# is set, otherwise return it unchanged. ENVUP_GH_MIRROR is a proxy *prefix*
# (e.g. https://ghproxy.com): the original URL is appended to it, which is the
# common CN-mirror pattern and works for both `git clone` and raw downloads.
# Unset => zero change to default behavior.
gh_url() {
    local u="$1"
    [[ -n "${ENVUP_GH_MIRROR:-}" ]] || { printf '%s' "$u"; return 0; }
    printf '%s/%s' "${ENVUP_GH_MIRROR%/}" "$u"
}

ENVUP_NET_TIMEOUT="${ENVUP_NET_TIMEOUT:-120}"
ENVUP_NET_TIMEOUT_INSTALLER="${ENVUP_NET_TIMEOUT_INSTALLER:-300}"
# Grace period after the soft timeout before SIGKILL. Without this a process
# wedged in a network syscall ignores SIGTERM and keeps the install "hung"
# well past the budget.
ENVUP_NET_KILL_AFTER="${ENVUP_NET_KILL_AFTER:-10}"
# Outer watchdog budget for a whole module hook (run_module_hook). Generous so
# legitimately slow installs aren't cut, but bounded so nothing hangs forever.
ENVUP_MODULE_TIMEOUT="${ENVUP_MODULE_TIMEOUT:-900}"
# Returned when a step needed the network and there isn't any. Distinct from a
# generic failure so callers can degrade instead of reporting a bug.
ENVUP_RC_OFFLINE=78

# net_run [--timeout N] "<desc>" -- <cmd>...    (output to terminal)
net_run() {
    local budget="$ENVUP_NET_TIMEOUT"
    [[ "$1" == --timeout ]] && { budget="$2"; shift 2; }
    local desc="$1"; shift; [[ "$1" == -- ]] && shift
    local t; t=$(timeout_bin)
    log_info "$desc (${budget}s timeout)"
    if [[ -n "$t" ]]; then "$t" -k "$ENVUP_NET_KILL_AFTER" "$budget" "$@"; else "$@"; fi
}

# log_run "<desc>" -- <cmd>... : run a command quietly (output -> log file),
# returning the command's exit status. For local (non-network) steps.
log_run() {
    local desc="$1"; shift; [[ "$1" == -- ]] && shift
    _logf RUN "$desc | $*"
    "$@" >>"${ENVUP_LOG_FILE:-/dev/stderr}" 2>&1
}

# net_run_logged: like net_run but redirects noisy installer output to the log.
net_run_logged() {
    local budget="$ENVUP_NET_TIMEOUT_INSTALLER"
    [[ "$1" == --timeout ]] && { budget="$2"; shift 2; }
    local desc="$1"; shift; [[ "$1" == -- ]] && shift
    local t; t=$(timeout_bin)
    log_info "$desc (${budget}s timeout)"
    if [[ -n "$t" ]]; then "$t" -k "$ENVUP_NET_KILL_AFTER" "$budget" "$@" >>"${ENVUP_LOG_FILE:-/dev/stderr}" 2>&1
    else "$@" >>"${ENVUP_LOG_FILE:-/dev/stderr}" 2>&1; fi
}

# ---- downloads -----------------------------------------------------------
# net_fetch <url> [dest] — fetch <url> (rewritten through the mirror) to <dest>,
# or to stdout when <dest> is omitted or "-". Prefers curl, falls back to wget,
# fails with a usable message when neither is installed.
#
# This is what module code should call instead of curl. It gets the mirror, the
# proxy, the offline check, the retries and the timeout for free — and the URL
# it actually used lands in the log, which is the difference between "the
# install failed" and "the install failed because the mirror 404s that asset".
net_fetch() {
    local url="$1" dest="${2:--}" real
    real="$(gh_url "$url")"

    # Dry-run first: a preview must not reach the network, not even to ask
    # whether the network is there.
    if [[ "${ENVUP_DRY_RUN:-0}" == 1 ]]; then
        log_info "[dry-run] fetch $real -> $dest"; return 0
    fi
    if ! net_online; then
        log_error "offline: cannot fetch $real"
        return "$ENVUP_RC_OFFLINE"
    fi
    log_debug "fetch $real -> $dest"

    local -a cmd
    if have curl; then
        cmd=(curl -fsSL --retry 2 --retry-delay 1 --connect-timeout 10 -o "$dest" "$real")
    elif have wget; then
        cmd=(wget -q --tries=3 --timeout=30 -O "$dest" "$real")
    else
        log_error "no curl and no wget — cannot download $real"
        log_hint "install one of them, or fetch the file yourself and re-run"
        return 1
    fi
    [[ "$dest" != - ]] && mkdir -p "$(dirname "$dest")"
    net_run "download $(basename "${url%%\?*}")" -- "${cmd[@]}"
}

# net_clone <repo-url> <dest> [extra git args...] — clone through the mirror.
# Shallow by default: envup wants a working tree, never the history, and on a
# slow link the difference is minutes. Pass --depth 0 to opt out.
net_clone() {
    local url="$1" dest="$2"; shift 2
    local real; real="$(gh_url "$url")"

    if [[ -d "$dest/.git" ]]; then
        log_info "already cloned: $dest"; return 0
    fi
    if [[ "${ENVUP_DRY_RUN:-0}" == 1 ]]; then
        log_info "[dry-run] git clone $real $dest"; return 0
    fi
    if ! net_online; then
        log_error "offline: cannot clone $real"
        return "$ENVUP_RC_OFFLINE"
    fi
    have git || { log_error "git is not installed — cannot clone $real"; return 1; }

    local -a depth=(--depth 1)
    if [[ "${1:-}" == --depth && "${2:-}" == 0 ]]; then depth=(); shift 2; fi
    mkdir -p "$(dirname "$dest")"
    net_run --timeout "$ENVUP_NET_TIMEOUT_INSTALLER" "clone $(basename "$dest")" \
        -- git clone --quiet "${depth[@]+"${depth[@]}"}" "$@" "$real" "$dest"
}

# ---- git submodule plugins (zsh/tmux) ------------------------------------
# Lives here because it is a network fetch like any other: the plugins come from
# GitHub over the same link, with the same failure modes.
# submodule_ensure <module> <plugin_dir>... : init submodules + verify non-empty.
submodule_ensure() {
    local mod="$1"; shift
    if [[ "${ENVUP_DRY_RUN:-0}" == 1 ]]; then
        log_info "[dry-run] git submodule update --init --recursive"; return 0
    fi
    ( cd "$ENVUP_HOME" && net_run "$mod submodules" -- git submodule update --init --recursive --quiet ) \
        || log_warn "[$mod] submodule update failed; verifying plugin contents"
    local d miss=()
    for d in "$@"; do
        [[ -d "$d" && -n "$(ls -A "$d" 2>/dev/null)" ]] || miss+=("$(basename "$d")")
    done
    if (( ${#miss[@]} )); then
        log_error "[$mod] plugins missing or empty: ${miss[*]}"
        log_hint "git -C $ENVUP_HOME submodule update --init --recursive"
        return 1
    fi
}
