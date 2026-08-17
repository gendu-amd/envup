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

# The hosts a GitHub proxy actually fronts. Anything else is somebody's own
# vendor domain and must be left alone — see gh_url.
_GH_HOSTS='github.com|raw.githubusercontent.com|api.github.com|objects.githubusercontent.com|codeload.github.com|gist.githubusercontent.com'

# gh_url <url> — rewrite a GitHub URL through a mirror/proxy when ENVUP_GH_MIRROR
# is set, otherwise return it unchanged. ENVUP_GH_MIRROR is a proxy *prefix*
# (e.g. https://ghproxy.com): the original URL is appended to it, which is the
# common CN-mirror pattern and works for both `git clone` and raw downloads.
# Unset => zero change to default behavior.
#
# Only GitHub hosts are rewritten. net_fetch and net_clone route *every* URL
# through here — that is the single-door design — so an unconditional prefix
# turned a vendor's own installer (atuin's https://setup.atuin.sh) into
# https://mirror/https://setup.atuin.sh on exactly the machines that need a
# mirror most. A GitHub proxy cannot serve a host it has never heard of.
gh_url() {
    local u="$1"
    [[ -n "${ENVUP_GH_MIRROR:-}" ]] || { printf '%s' "$u"; return 0; }
    # scheme-relative and bare git@ forms included: ssh never goes via a proxy.
    [[ "$u" =~ ^https?://($_GH_HOSTS)(/|$) ]] || { printf '%s' "$u"; return 0; }
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

# ---- integrity -----------------------------------------------------------
# What a checksum is worth here, precisely: it is published in the same release
# and fetched over the same link, so it does not protect you from an upstream
# that was compromised or a mirror that is actively hostile — either can serve a
# matching pair. What it catches is the download that simply arrived wrong, and
# that is the one that actually happens: a corporate proxy answering 200 with a
# captive-portal page, a transfer truncated at the byte the link dropped, a
# mirror a week stale handing back the previous release. All three install
# without complaint and go wrong later, somewhere with no obvious connection to
# the download.

# net_digest <file> <bits> — lowercase hex digest, or nothing if this machine
# cannot compute one. Three implementations because there is no one command:
# coreutils on Linux, shasum (perl) on everything Apple ships, openssl on the
# stripped images that have neither.
net_digest() {
    local f="$1" bits="$2" out="" re
    if   have "sha${bits}sum"; then out="$("sha${bits}sum" "$f" 2>/dev/null)"
    elif have shasum;          then out="$(shasum -a "$bits" "$f" 2>/dev/null)"
    elif have openssl;         then out="$(openssl dgst "-sha$bits" "$f" 2>/dev/null)"
    else return 1
    fi
    # coreutils and shasum print "<hex>  <name>"; openssl prints
    # "SHA256(<name>)= <hex>". Pull the digest out by its shape rather than by
    # field number, and the difference stops mattering.
    re="[0-9a-fA-F]{$((bits / 4))}"
    [[ "$out" =~ $re ]] || return 1
    tr '[:upper:]' '[:lower:]' <<<"${BASH_REMATCH[0]}" | tr -d '\n'
}

# net_sum_lookup <sums-file> <name> — the digest that file claims for <name>.
# Three layouts in the wild: GNU ("<hex>  name", "<hex> *name" for binary), BSD
# and openssl ("SHA256 (name) = <hex>"), and a sidecar holding nothing but the
# number. A manifest may also carry a path, so only the basename is compared.
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

# net_verify_file <file> <sums-file> [name-in-that-file] — three answers, not
# two, because "the digests disagree" and "there is nothing to compare against"
# call for completely different handling by the caller.
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

# net_sum_url <asset-url> <every asset url...> — pick the file in the same
# release that vouches for the chosen asset. Sidecar first, because it is
# unambiguous.
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
    # Otherwise one manifest for the whole release. goreleaser writes
    # checksums.txt, neovim writes shasum.txt, fzf writes
    # <name>_<version>_checksums.txt.
    for u in "$@"; do
        b="$(tr '[:upper:]' '[:lower:]' <<<"${u##*/}")"
        case "$b" in
            *checksums.txt|checksums|sha256sums*|sha256sum.txt|sha512sums*|shasum.txt)
                printf '%s' "$u"; return 0 ;;
        esac
    done
    return 1
}

# Plenty of upstreams publish nothing — fd, bat and delta among them — so an
# absent checksum cannot be fatal by default or those modules simply stop
# installing. ENVUP_REQUIRE_CHECKSUM=1 makes it fatal, which is what you want
# when ENVUP_GH_MIRROR points at a proxy you do not run.
_net_unverified() {
    local label="$1"
    if [[ "${ENVUP_REQUIRE_CHECKSUM:-0}" == 1 ]]; then
        log_error "[$label] $2, and ENVUP_REQUIRE_CHECKSUM=1"
        return 1
    fi
    log_debug "[$label] not verified: $2"
}

# net_check_asset <label> <file> <asset-url> <tmpdir> <every asset url...>
# Find the release's checksum manifest, fetch it, and compare. Returns 0 when
# the file is trustworthy *or* when nothing could vouch for it and that is
# allowed; non-zero only when the download should not be used.
net_check_asset() {
    local label="$1" file="$2" asset="$3" tmp="$4"; shift 4
    local sumurl rc sums="$tmp/sums"

    sumurl="$(net_sum_url "$asset" "$@")" \
        || { _net_unverified "$label" "this release publishes no checksums"; return $?; }

    # Quietly: a 404 on the sums file is a thing we handle, not a thing to
    # print curl's opinion of.
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
