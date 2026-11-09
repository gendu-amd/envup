#!/bin/bash
# Centralized, mirrored/offline-aware, time-bounded network operations.

# Only these hosts may be rewritten through a GitHub mirror.
_GH_HOSTS='github.com|raw.githubusercontent.com|api.github.com|objects.githubusercontent.com|codeload.github.com|gist.githubusercontent.com'

# gh_url <url> — prefix GitHub URLs with ENVUP_GH_MIRROR; leave vendors alone.
gh_url() {
    local u="$1"
    [[ -n "${ENVUP_GH_MIRROR:-}" ]] || { printf '%s' "$u"; return 0; }
    [[ "$u" =~ ^https?://($_GH_HOSTS)(/|$) ]] || { printf '%s' "$u"; return 0; }
    printf '%s/%s' "${ENVUP_GH_MIRROR%/}" "$u"
}

ENVUP_NET_TIMEOUT="${ENVUP_NET_TIMEOUT:-120}"
ENVUP_NET_TIMEOUT_INSTALLER="${ENVUP_NET_TIMEOUT_INSTALLER:-300}"
# Grace period between timeout's TERM and KILL.
ENVUP_NET_KILL_AFTER="${ENVUP_NET_KILL_AFTER:-10}"
ENVUP_MODULE_TIMEOUT="${ENVUP_MODULE_TIMEOUT:-900}"
# Distinct status lets providers degrade instead of reporting a fault.
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

# net_fetch <url> [dest] — mirrored curl/wget fetch; "-" writes to stdout.
net_fetch() {
    local url="$1" dest="${2:--}" real
    real="$(gh_url "$url")"

    # Dry-run must not perform even the network probe.
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

# net_clone <url> <dest> [args...] — shallow mirrored clone; --depth 0 opts out.
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

# Release checksums detect corrupt, truncated, or stale downloads.

# net_digest <file> <bits> — use coreutils, shasum, or openssl.
net_digest() {
    local f="$1" bits="$2" out="" re
    if   have "sha${bits}sum"; then out="$("sha${bits}sum" "$f" 2>/dev/null)"
    elif have shasum;          then out="$(shasum -a "$bits" "$f" 2>/dev/null)"
    elif have openssl;         then out="$(openssl dgst "-sha$bits" "$f" 2>/dev/null)"
    else return 1
    fi
    # Extract by shape because output field positions differ.
    re="[0-9a-fA-F]{$((bits / 4))}"
    [[ "$out" =~ $re ]] || return 1
    tr '[:upper:]' '[:lower:]' <<<"${BASH_REMATCH[0]}" | tr -d '\n'
}

# Parse GNU, BSD/openssl, and digest-only checksum formats.
net_sum_lookup() {
    local f="$1" want="$2" line hex name
    [[ -r "$f" ]] || return 1
    while IFS= read -r line || [[ -n "$line" ]]; do
        if   [[ "$line" =~ ^[[:space:]]*([0-9a-fA-F]{64,128})[[:space:]]*$ ]]; then
            hex="${BASH_REMATCH[1]}"; name="$want"
        elif [[ "$line" =~ ^[[:space:]]*([0-9a-fA-F]{64,128})[[:space:]]+\*?([^[:space:]]+) ]]; then
            hex="${BASH_REMATCH[1]}"; name="${BASH_REMATCH[2]}"
        elif [[ "$line" =~ \(([^\)]+)\)[[:space:]]*=[[:space:]]*([0-9a-fA-F]{64,128})[[:space:]]*$ ]]; then
            name="${BASH_REMATCH[1]}"; hex="${BASH_REMATCH[2]}"
        else
            continue
        fi
        [[ "${name##*/}" == "$want" ]] || continue
        case "${#hex}" in 64|128) ;; *) continue ;; esac
        tr '[:upper:]' '[:lower:]' <<<"$hex" | tr -d '\n'
        return 0
    done < "$f"
    return 1
}

# net_verify_file returns match, mismatch, or unverifiable.
#   0  match
#   1  mismatch — this file is not what the release says it is
#   2  cannot tell: no digest for this name, or no tool here to compute one
net_verify_file() {
    local f="$1" sums="$2" name="${3:-$(basename "$1")}" want got bits
    want="$(net_sum_lookup "$sums" "$name")" || {
        log_debug "$(basename "$sums") lists no digest for $name"
        return 2
    }
    case "${#want}" in
        64)  bits=256 ;;
        128) bits=512 ;;
        *)   return 2 ;;
    esac
    got="$(net_digest "$f" "$bits")" || {
        log_debug "no sha$bits tool here (sha${bits}sum, shasum, openssl) — cannot check $name"
        return 2
    }
    [[ "$got" == "$want" ]] && return 0
    log_error "$name failed its sha$bits check"
    log_error "  expected $want"
    log_error "  got      $got"
    return 1
}

# Prefer an asset sidecar, then a release-wide checksum manifest.
net_sum_url() {
    local asset="$1"; shift
    local base="${asset##*/}" u b
    for u in "$@"; do
        b="${u##*/}"
        if [[ "$b" == "$base".sha256 || "$b" == "$base".sha256sum \
           || "$b" == "$base".sha512 || "$b" == "$base".sum ]]; then
            printf '%s' "$u"; return 0
        fi
    done
    # Common release-wide manifest names.
    for u in "$@"; do
        b="$(tr '[:upper:]' '[:lower:]' <<<"${u##*/}")"
        case "$b" in
            *checksums.txt|checksums|sha256sums*|sha256sum.txt|sha512sums*|shasum.txt)
                printf '%s' "$u"; return 0 ;;
        esac
    done
    return 1
}

# Missing checksums are optional unless ENVUP_REQUIRE_CHECKSUM=1.
_net_unverified() {
    local label="$1"
    if [[ "${ENVUP_REQUIRE_CHECKSUM:-0}" == 1 ]]; then
        log_error "[$label] $2, and ENVUP_REQUIRE_CHECKSUM=1"
        return 1
    fi
    log_debug "[$label] not verified: $2"
}

# net_check_asset <label> <file> <asset-url> <tmpdir> <every asset url...>
# Return non-zero only when the asset must not be used.
net_check_asset() {
    local label="$1" file="$2" asset="$3" tmp="$4"; shift 4
    local sumurl rc sums="$tmp/sums"

    sumurl="$(net_sum_url "$asset" "$@")" \
        || { _net_unverified "$label" "this release publishes no checksums"; return $?; }

    # A missing sums file is handled by policy, so keep transport noise in logs.
    if ! net_fetch "$sumurl" "$sums" >>"${ENVUP_LOG_FILE:-/dev/null}" 2>&1; then
        _net_unverified "$label" "could not download $(basename "$sumurl")"; return $?
    fi

    net_verify_file "$file" "$sums" "$(basename "${asset%%\?*}")"; rc=$?
    case "$rc" in
        0) log_debug "[$label] $(basename "$file") matches $(basename "$sumurl")" ;;
        1) return 1 ;;
        *) _net_unverified "$label" "$(basename "$sumurl") had nothing usable for this asset"; return $? ;;
    esac
}

# ---- git submodule plugins (zsh/tmux) ------------------------------------
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
