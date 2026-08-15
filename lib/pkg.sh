#!/bin/bash
# ============================================
# envup — system package managers
# ============================================
# Detects the one manager this machine has and exposes a single entry point,
# pkg_install. Note what it deliberately does NOT do: assume it can run. On a
# server where the only manager is apt and we have no route to root, this layer
# reports that it cannot install rather than shelling out and letting the user
# read a permission error from inside dpkg. Saying "I can't" is what lets the
# provider chain go and find a user-space route instead.
#
# Depends on: log.sh, caps.sh, net.sh
# ============================================

# The manager, and how to drive it. _PKG_ROOT records whether it needs
# privileges at all — Homebrew famously refuses to run under sudo.
ENVUP_PKG=unknown; _PKG_INSTALL=(); _PKG_UPDATE=(); _PKG_ROOT=1
if   have apt-get; then ENVUP_PKG=apt;    _PKG_INSTALL=(apt-get install -y);      _PKG_UPDATE=(apt-get update)
elif have dnf;     then ENVUP_PKG=dnf;    _PKG_INSTALL=(dnf install -y);          _PKG_UPDATE=(dnf makecache)
elif have yum;     then ENVUP_PKG=yum;    _PKG_INSTALL=(yum install -y);          _PKG_UPDATE=(yum makecache)
elif have pacman;  then ENVUP_PKG=pacman; _PKG_INSTALL=(pacman -S --noconfirm);   _PKG_UPDATE=(pacman -Sy)
elif have brew;    then ENVUP_PKG=brew;   _PKG_INSTALL=(brew install);            _PKG_UPDATE=(brew update); _PKG_ROOT=0
elif have apk;     then ENVUP_PKG=apk;    _PKG_INSTALL=(apk add --no-cache);      _PKG_UPDATE=(apk update)
fi

# A system manager we cannot invoke is worth less than a user-space one we can.
# Homebrew on Linux installs entirely under $HOME, so on a no-root server it is
# strictly the better choice — and it is the only one of these that ever works
# there.
if (( _PKG_ROOT )) && ! priv_available && have brew; then
    log_debug "no route to root; preferring user-space brew over $ENVUP_PKG"
    ENVUP_PKG=brew; _PKG_INSTALL=(brew install); _PKG_UPDATE=(brew update); _PKG_ROOT=0
fi

# Splice the privilege prefix into the argv rather than wrapping the call in a
# function: these arrays are handed to `timeout`, which can exec a program but
# not a shell function.
if (( _PKG_ROOT )) && (( ${#_PKG_INSTALL[@]} )); then
    _PKG_INSTALL=("${ENVUP_PRIV_ARGV[@]+"${ENVUP_PRIV_ARGV[@]}"}" "${_PKG_INSTALL[@]}")
    _PKG_UPDATE=("${ENVUP_PRIV_ARGV[@]+"${ENVUP_PRIV_ARGV[@]}"}" "${_PKG_UPDATE[@]}")
fi

# Exported so module hooks (run in subshells by run_module_hook) and `envup
# status` can read the detected package manager. The arrays cannot be exported,
# which is precisely why the hook subshell re-sources this library.
export ENVUP_PKG

# pkg_family — the packaging tradition, which is the right key for a
# cross-distro package-name table: every Debian derivative calls fd "fd-find"
# whatever its ID says.
pkg_family() {
    case "$ENVUP_PKG" in
        apt)     echo debian ;;
        dnf|yum) echo rhel ;;
        pacman)  echo arch ;;
        apk)     echo alpine ;;
        brew)    echo brew ;;
        *)       echo unknown ;;
    esac
}

# pkg_can_install — can this machine install system packages at all, right now?
# Ask before offering to; the answer is no more often than you'd think.
pkg_can_install() {
    (( ${#_PKG_INSTALL[@]} )) || return 1
    if (( _PKG_ROOT )); then priv_available || return 1; fi
    return 0
}

# pkg_why_not — one line explaining a false from pkg_can_install, for the log.
pkg_why_not() {
    if (( ${#_PKG_INSTALL[@]} == 0 )); then
        echo "no supported package manager (apt/dnf/yum/pacman/brew/apk)"
    elif (( _PKG_ROOT )) && ! priv_available; then
        echo "$ENVUP_PKG needs root and this machine gives us no route to it (ENVUP_PRIV=$ENVUP_PRIV)"
    else
        echo "package installation unavailable"
    fi
}

_pkg_updated="${_pkg_updated:-0}"   # inherit "already refreshed" across hook subshells

# Install system packages. Output flows to the terminal (sudo prompts visible)
# and is tee'd to the log. Honours ENVUP_DRY_RUN. Lazy `update` on first use.
pkg_install() {
    [[ $# -eq 0 ]] && return 0

    # Dry-run reports and returns success even when the install could not
    # actually happen: a preview that fails is no longer a preview. It does say
    # so, though — finding out here beats finding out on the real run.
    if [[ "${ENVUP_DRY_RUN:-0}" == 1 ]]; then
        if pkg_can_install; then log_info "[dry-run] ${_PKG_INSTALL[*]} $*"
        else log_info "[dry-run] would install: $* — except that $(pkg_why_not)"; fi
        return 0
    fi
    if ! pkg_can_install; then
        log_error "$(pkg_why_not)"
        log_hint "install manually: $*"
        return "$ENVUP_RC_NOPRIV"
    fi

    # Wrap the package manager in a timeout too — a stuck mirror or repo lock
    # must not hang the whole run (see run_module_hook's watchdog).
    local t rc; t=$(timeout_bin); local ib="$ENVUP_NET_TIMEOUT_INSTALLER"
    if [[ $_pkg_updated == 0 && ${#_PKG_UPDATE[@]} -gt 0 ]]; then
        log_info "refreshing package lists"
        if [[ -n "$t" ]]; then "$t" -k "$ENVUP_NET_KILL_AFTER" "$ib" "${_PKG_UPDATE[@]}" 2>&1 | tee -a "$ENVUP_LOG_FILE"
        else "${_PKG_UPDATE[@]}" 2>&1 | tee -a "$ENVUP_LOG_FILE"; fi
        # PIPESTATUS, not $?: the pipeline ends in tee, which succeeds no matter
        # what the package manager did. $? is only the right answer when the
        # caller happens to have set pipefail, and this must not depend on that.
        rc=${PIPESTATUS[0]}
        if (( rc == 0 )); then
            _pkg_updated=1; export _pkg_updated
        else
            # Do NOT mark the cache fresh on failure. Marking it meant the next
            # install ran against a stale or empty index and failed with
            # "package not found" — a message that sends you looking for a
            # missing package when the real problem was an unreachable mirror
            # (typically: a proxy sudo just stripped, or no network at all).
            log_warn "package list refresh failed (rc=$rc) — using whatever index is already on disk"
            log_hint "if the next step reports a missing package, that is why: check the log for the mirror error"
        fi
    fi

    log_info "installing: $*"
    if [[ -n "$t" ]]; then "$t" -k "$ENVUP_NET_KILL_AFTER" "$ib" "${_PKG_INSTALL[@]}" "$@" 2>&1 | tee -a "$ENVUP_LOG_FILE"
    else "${_PKG_INSTALL[@]}" "$@" 2>&1 | tee -a "$ENVUP_LOG_FILE"; fi
    return "${PIPESTATUS[0]}"
}
