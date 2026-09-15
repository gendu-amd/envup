#!/bin/bash
# Capability detection. Results are exported and reused by hook subshells.
# Most may be preset for tests; supported user overrides are documented.

# ---- timeout binary ------------------------------------------------------
# Homebrew installs GNU timeout as gtimeout.
timeout_bin() { if have timeout; then echo timeout; elif have gtimeout; then echo gtimeout; fi; }

# _caps_capped <secs> <cmd>... — bound probes when timeout is available.
_caps_capped() {
    local secs="$1"; shift
    local t; t="$(timeout_bin)"
    if [[ -n "$t" ]]; then "$t" -k 2 "$secs" "$@"; else "$@"; fi
}

# ---- OS / platform -------------------------------------------------------
# Keep this rule aligned with .zshrc.d/20-platform.zsh:
#   Darwin -> macos; Linux+microsoft -> wsl2; Linux+(dockerenv|cgroup) -> docker;
#   Linux -> linux; anything else -> linux (fallback).
if [[ -z "${ENVUP_PLATFORM:-}" ]]; then
    case "$(uname -s)" in
        Darwin) ENVUP_PLATFORM=macos ;;
        Linux)  if grep -qi microsoft /proc/version 2>/dev/null; then ENVUP_PLATFORM=wsl2
                elif [[ -f /.dockerenv ]] || grep -q 'docker\|containerd' /proc/1/cgroup 2>/dev/null; then ENVUP_PLATFORM=docker
                else ENVUP_PLATFORM=linux; fi ;;
        *)      ENVUP_PLATFORM=linux ;;
    esac
fi

# ENVUP_OS is macos/linux; ENVUP_PLATFORM also distinguishes WSL2/Docker.
if [[ -z "${ENVUP_OS:-}" ]]; then
    if [[ "$ENVUP_PLATFORM" == macos ]]; then ENVUP_OS=macos; else ENVUP_OS=linux; fi
fi

# ---- distribution --------------------------------------------------------
# Distribution ID and ID_LIKE from os-release.
if [[ -z "${ENVUP_DISTRO:-}" ]]; then
    ENVUP_DISTRO=unknown; ENVUP_DISTRO_VER=""; ENVUP_DISTRO_LIKE=""
    if [[ "$ENVUP_OS" == macos ]]; then
        ENVUP_DISTRO=macos
        ENVUP_DISTRO_VER="$(sw_vers -productVersion 2>/dev/null || echo "")"
    elif [[ -r /etc/os-release ]]; then
        # Source os-release in a subshell so its variables cannot leak.
        IFS='|' read -r ENVUP_DISTRO ENVUP_DISTRO_VER ENVUP_DISTRO_LIKE < <(
            # shellcheck source=/dev/null
            . /etc/os-release 2>/dev/null
            printf '%s|%s|%s\n' "${ID:-unknown}" "${VERSION_ID:-}" "${ID_LIKE:-}"
        )
        ENVUP_DISTRO="${ENVUP_DISTRO:-unknown}"
    fi
fi

# ---- architecture --------------------------------------------------------
# Normalize uname spellings for release asset matching.
ENVUP_ARCH_RAW="${ENVUP_ARCH_RAW:-$(uname -m 2>/dev/null || echo unknown)}"
# Normalize inherited values too; zsh exports the raw uname spelling.
case "${ENVUP_ARCH:-$ENVUP_ARCH_RAW}" in
    x86_64|amd64|x64)          ENVUP_ARCH=x86_64 ;;
    aarch64|arm64)             ENVUP_ARCH=aarch64 ;;
    armv7l|armv7|armhf|armv6l) ENVUP_ARCH=armv7 ;;
    i386|i486|i586|i686|x86)   ENVUP_ARCH=i686 ;;
    ppc64le)                   ENVUP_ARCH=ppc64le ;;
    riscv64)                   ENVUP_ARCH=riscv64 ;;
    s390x)                     ENVUP_ARCH=s390x ;;
    *)                         ENVUP_ARCH="$ENVUP_ARCH_RAW" ;;
esac

# ---- libc ----------------------------------------------------------------
# ABI for release selection: darwin, musl, glibc-<version>, or unknown.
_caps_libc() {
    [[ "$ENVUP_OS" == macos ]] && { printf 'darwin'; return 0; }

    # The musl loader is more reliable than BusyBox ldd output.
    compgen -G '/lib/ld-musl-*.so.1' >/dev/null 2>&1 && { printf 'musl'; return 0; }

    local v
    v="$(getconf GNU_LIBC_VERSION 2>/dev/null)"          # "glibc 2.32"
    if [[ "$v" == glibc\ * ]]; then printf 'glibc-%s' "${v#glibc }"; return 0; fi

    # GNU and musl ldd use different streams/statuses; inspect combined output.
    v="$(ldd --version 2>&1 | head -n1)"
    [[ "$v" == *musl* ]] && { printf 'musl'; return 0; }
    v="$(printf '%s' "$v" | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?$' | head -n1)"
    [[ -n "$v" ]] && { printf 'glibc-%s' "$v"; return 0; }

    printf 'unknown'
}
ENVUP_LIBC="${ENVUP_LIBC:-$(_caps_libc)}"

# ---- privilege -----------------------------------------------------------
# Values:
#   root              already uid 0; run privileged commands directly
#   sudo              sudo works without a password; safe to use unattended
#   sudo-interactive  sudo needs a password and we have a terminal to type into
#   none              no path to root — providers must find a user-space route
_caps_priv() {
    (( EUID == 0 )) && { printf 'root'; return 0; }
    have sudo || { printf 'none'; return 0; }

    _caps_capped 5 sudo -n true 2>/dev/null && { printf 'sudo'; return 0; }

    # Distinguish a password prompt with a TTY from no sudo rights.
    local why; why="$(_caps_capped 5 sudo -nv 2>&1)"
    if [[ "$why" == *password* && -t 0 ]]; then printf 'sudo-interactive'; return 0; fi
    printf 'none'
}
ENVUP_PRIV="${ENVUP_PRIV:-$(_caps_priv)}"

# proxy_env_set — true when this shell carries proxy settings that a privileged
# command would need to inherit to reach anything.
proxy_env_set() {
    [[ -n "${http_proxy:-}"  || -n "${HTTP_PROXY:-}"  ||
       -n "${https_proxy:-}" || -n "${HTTPS_PROXY:-}" ||
       -n "${all_proxy:-}"   || -n "${ALL_PROXY:-}" ]]
}

# Probe sudo -E because proxy variables may be required and sudoers may forbid it.
if [[ -z "${ENVUP_PRIV_KEEP_ENV:-}" ]]; then
    ENVUP_PRIV_KEEP_ENV=0
    if proxy_env_set; then
        case "$ENVUP_PRIV" in
            sudo)
                if _caps_capped 5 sudo -n -E true 2>/dev/null; then
                    ENVUP_PRIV_KEEP_ENV=1
                else
                    log_warn "sudo refuses -E: proxy variables will be stripped from privileged commands"
                    log_hint "add: Defaults env_keep += \"http_proxy https_proxy no_proxy\"  (or install without root)"
                fi ;;
            # Probing this case would trigger the password prompt.
            sudo-interactive) ENVUP_PRIV_KEEP_ENV=1 ;;
        esac
    fi
fi

# argv prefix lets timeout wrap privileged package-manager commands directly.
ENVUP_PRIV_ARGV=()
case "$ENVUP_PRIV" in
    sudo)             ENVUP_PRIV_ARGV=(sudo -n) ;;
    sudo-interactive) ENVUP_PRIV_ARGV=(sudo) ;;
esac
if (( ${#ENVUP_PRIV_ARGV[@]} )) && (( ENVUP_PRIV_KEEP_ENV )); then ENVUP_PRIV_ARGV+=(-E); fi

priv_available() { [[ "$ENVUP_PRIV" == root || "$ENVUP_PRIV" == sudo || "$ENVUP_PRIV" == sudo-interactive ]]; }

# priv_run <cmd>... — run as root; 77 means privileges are unavailable.
ENVUP_RC_NOPRIV=77
priv_run() {
    if ! priv_available; then
        log_error "this needs root and this machine gives us no route to it: $*"
        return "$ENVUP_RC_NOPRIV"
    fi
    "${ENVUP_PRIV_ARGV[@]+"${ENVUP_PRIV_ARGV[@]}"}" "$@"
}

# ---- host + home ---------------------------------------------------------
ENVUP_HOST="${ENVUP_HOST:-$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo unknown)}"
ENVUP_HOST="${ENVUP_HOST%%.*}"

# Detect common network filesystems so state can be host-scoped.
_caps_home_shared() {
    local fs=""
    # GNU stat prints the filesystem type directly; BSD stat has no equivalent.
    fs="$(stat -f -c %T "$HOME" 2>/dev/null || echo "")"
    [[ -z "$fs" ]] && fs="$(df -PT "$HOME" 2>/dev/null | awk 'NR==2{print $2}')"
    case "$fs" in
        nfs*|cifs|smb*|autofs|afs|lustre|gpfs|beegfs|fuse.sshfs|fuse.glusterfs) printf 1; return 0 ;;
    esac
    # Portable fallback: network devices commonly look like host:/export.
    local dev; dev="$(df -P "$HOME" 2>/dev/null | awk 'NR==2{print $1}')"
    [[ "$dev" == *:/* ]] && { printf 1; return 0; }
    printf 0
}
ENVUP_HOME_SHARED="${ENVUP_HOME_SHARED:-$(_caps_home_shared)}"

# ---- network -------------------------------------------------------------
# Probed lazily and exported. Values:
#   direct   github.com is reachable
#   mirror   github.com is not, but ENVUP_GH_MIRROR is — rewrite and carry on
#   offline  neither; providers must skip network steps and say so
#
# ENVUP_OFFLINE=1 skips the probe.
ENVUP_NET_PROBE_TIMEOUT="${ENVUP_NET_PROBE_TIMEOUT:-5}"
_caps_reachable() {
    local url="$1"
    if have curl; then
        curl -fsS -o /dev/null --max-time "$ENVUP_NET_PROBE_TIMEOUT" --head "$url" 2>/dev/null && return 0
        # Some mirrors reject HEAD but serve GET; one byte is enough to know.
        curl -fsS -o /dev/null --max-time "$ENVUP_NET_PROBE_TIMEOUT" -r 0-0 "$url" 2>/dev/null
    elif have wget; then
        wget -q --spider --timeout="$ENVUP_NET_PROBE_TIMEOUT" --tries=1 "$url" 2>/dev/null
    else
        return 1
    fi
}
caps_net() {
    if [[ -n "${ENVUP_NET:-}" ]]; then printf '%s' "$ENVUP_NET"; return 0; fi
    if [[ "${ENVUP_OFFLINE:-0}" == 1 ]]; then
        ENVUP_NET=offline
    elif [[ -n "${ENVUP_GH_MIRROR:-}" ]] && _caps_reachable "${ENVUP_GH_MIRROR%/}/"; then
        # An explicit mirror takes precedence over the direct route.
        ENVUP_NET=mirror
    elif _caps_reachable "https://github.com"; then
        ENVUP_NET=direct
    else
        ENVUP_NET=offline
    fi
    export ENVUP_NET
    log_debug "network: $ENVUP_NET"
    printf '%s' "$ENVUP_NET"
}
net_online() { [[ "$(caps_net)" != offline ]]; }

# ---- summary -------------------------------------------------------------
# ENVUP_PKG loads later, so read it at call time.
caps_summary() {
    printf 'os=%s platform=%s distro=%s%s arch=%s libc=%s priv=%s pkg=%s host=%s shared_home=%s net=%s' \
        "$ENVUP_OS" "$ENVUP_PLATFORM" "$ENVUP_DISTRO" "${ENVUP_DISTRO_VER:+-$ENVUP_DISTRO_VER}" \
        "$ENVUP_ARCH" "$ENVUP_LIBC" "$ENVUP_PRIV" "${ENVUP_PKG:-unknown}" \
        "$ENVUP_HOST" "$ENVUP_HOME_SHARED" "${ENVUP_NET:-unprobed}"
}

export ENVUP_PLATFORM ENVUP_OS ENVUP_DISTRO ENVUP_DISTRO_VER ENVUP_DISTRO_LIKE
export ENVUP_ARCH ENVUP_ARCH_RAW ENVUP_LIBC
export ENVUP_PRIV ENVUP_PRIV_KEEP_ENV ENVUP_HOST ENVUP_HOME_SHARED
