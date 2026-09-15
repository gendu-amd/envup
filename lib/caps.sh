#!/bin/bash
# ============================================
# envup — capability detection
# ============================================
# What can this machine actually do? Every later decision reads these: which
# package manager to drive, whether to even try sudo, which release asset can
# execute here, whether $HOME is shared with other hosts.
#
# Two rules hold for every value below:
#
#   1. Idempotent. A value already present in the environment is trusted and
#      never re-probed. run_module_hook spawns a fresh bash per hook, and that
#      child re-sources this library — without the rule we would re-run
#      `sudo -n true` and the reachability probe once per module.
#   2. Exported. That is what makes rule 1 work across those subshells, and it
#      lets `envup status`/`doctor` report exactly the verdict the installer
#      acted on rather than a fresh guess.
#
# Set any of them yourself to override the probe (useful in tests, and on a
# machine whose sudo/network behaves in a way the heuristics get wrong):
#   ENVUP_PRIV=none ENVUP_NET=offline envup install
#
# Depends on: log.sh
# ============================================

# ---- timeout binary ------------------------------------------------------
# GNU coreutils' `timeout`, under whichever name this machine has it: Homebrew
# installs coreutils with a `g` prefix, so macOS calls it gtimeout. Prints
# nothing when there is none — callers then run the command unguarded, which is
# the honest degradation (and run_module_hook warns about it once).
timeout_bin() { if have timeout; then echo timeout; elif have gtimeout; then echo gtimeout; fi; }

# _caps_capped <secs> <cmd>... — run a probe under a hard time cap when we can.
# Probes in this file must not be able to hang the run: `sudo -n true` looks
# instant until sudoers lives in LDAP, and a reachability check is a network
# call by definition.
_caps_capped() {
    local secs="$1"; shift
    local t; t="$(timeout_bin)"
    if [[ -n "$t" ]]; then "$t" -k 2 "$secs" "$@"; else "$@"; fi
}

# ---- OS / platform -------------------------------------------------------
# Canonical platform-detection rule (see docs/ARCHITECTURE.md "Platform
# detection"). Kept identical to .zshrc.d/20-platform.zsh so the
# install-time (bash) and runtime (zsh) verdicts never drift:
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

# The OS family, as distinct from the platform flavour. wsl2 and docker are
# Linux for everything that matters here — package manager, release assets,
# libc — and differ only in shell-level tweaks. Code that wants "is this a Mac?"
# should ask ENVUP_OS; code that wants "am I inside a container?" wants
# ENVUP_PLATFORM.
if [[ -z "${ENVUP_OS:-}" ]]; then
    if [[ "$ENVUP_PLATFORM" == macos ]]; then ENVUP_OS=macos; else ENVUP_OS=linux; fi
fi

# ---- distribution --------------------------------------------------------
# ENVUP_DISTRO is the /etc/os-release ID (ubuntu, debian, fedora, rhel, arch,
# alpine, ...); ENVUP_DISTRO_LIKE is its ID_LIKE, which is what lets a package
# name table cover "anything Debian-ish" without enumerating every derivative.
if [[ -z "${ENVUP_DISTRO:-}" ]]; then
    ENVUP_DISTRO=unknown; ENVUP_DISTRO_VER=""; ENVUP_DISTRO_LIKE=""
    if [[ "$ENVUP_OS" == macos ]]; then
        ENVUP_DISTRO=macos
        ENVUP_DISTRO_VER="$(sw_vers -productVersion 2>/dev/null || echo "")"
    elif [[ -r /etc/os-release ]]; then
        # os-release is shell syntax by spec, but it is not *our* shell: source
        # it inside the substitution so its ID/VERSION_ID/NAME never leak here.
        IFS='|' read -r ENVUP_DISTRO ENVUP_DISTRO_VER ENVUP_DISTRO_LIKE < <(
            # shellcheck source=/dev/null
            . /etc/os-release 2>/dev/null
            printf '%s|%s|%s\n' "${ID:-unknown}" "${VERSION_ID:-}" "${ID_LIKE:-}"
        )
        ENVUP_DISTRO="${ENVUP_DISTRO:-unknown}"
    fi
fi

# ---- architecture --------------------------------------------------------
# `uname -m` is not a stable vocabulary: the same CPU answers arm64 on macOS and
# aarch64 on Linux, amd64 on some userlands and x86_64 on others. Release assets
# are named after one spelling or the other, so normalise once here and let the
# providers match against a known set. ENVUP_ARCH_RAW keeps the original for
# anything that genuinely wants the kernel's own word for it.
ENVUP_ARCH_RAW="${ENVUP_ARCH_RAW:-$(uname -m 2>/dev/null || echo unknown)}"
# Normalise unconditionally — including a value inherited from the environment.
# The zsh runtime layer exports ENVUP_ARCH too, straight from `uname -m`, so an
# envup run launched from an already-installed shell would otherwise inherit
# `arm64` on macOS and never normalise it. Re-normalising an already-normal
# value is a no-op, so this stays idempotent.
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
# Which C library a prebuilt binary has to link against. This is not a detail we
# can skip: a glibc build on Alpine dies with a bare "not found" (the loader
# isn't there), and a binary built against a newer glibc than the host's dies
# with "version GLIBC_2.34 not found". Both happen at exec time, long after the
# download looked successful, so providers need the answer up front.
# Values: darwin | musl | glibc-<major.minor> | unknown.
_caps_libc() {
    [[ "$ENVUP_OS" == macos ]] && { printf 'darwin'; return 0; }

    # Alpine and friends: the loader's filename is the giveaway, and it is there
    # even when `ldd` is a busybox stub that ignores --version.
    compgen -G '/lib/ld-musl-*.so.1' >/dev/null 2>&1 && { printf 'musl'; return 0; }

    local v
    v="$(getconf GNU_LIBC_VERSION 2>/dev/null)"          # "glibc 2.32"
    if [[ "$v" == glibc\ * ]]; then printf 'glibc-%s' "${v#glibc }"; return 0; fi

    # `ldd --version` prints to stdout and exits 0 on GNU, prints to stderr and
    # exits 1 on musl — so capture both streams and don't trust the status.
    v="$(ldd --version 2>&1 | head -n1)"
    [[ "$v" == *musl* ]] && { printf 'musl'; return 0; }
    v="$(printf '%s' "$v" | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?$' | head -n1)"
    [[ -n "$v" ]] && { printf 'glibc-%s' "$v"; return 0; }

    printf 'unknown'
}
ENVUP_LIBC="${ENVUP_LIBC:-$(_caps_libc)}"

# ---- privilege -----------------------------------------------------------
# The old test was `[[ $EUID -ne 0 ]] && have sudo`, which is wrong in the exact
# situation it matters most: on a locked-down server sudo *exists* but wants a
# password, so every `sudo apt-get install` sat at an invisible prompt until the
# 900s module watchdog killed it. `sudo -n` never prompts, so asking it first
# turns a fifteen-minute hang into an instant, accurate verdict.
#
# Values:
#   root              already uid 0; run privileged commands directly
#   sudo              sudo works without a password; safe to use unattended
#   sudo-interactive  sudo needs a password and we have a terminal to type into
#   none              no path to root — providers must find a user-space route
_caps_priv() {
    (( EUID == 0 )) && { printf 'root'; return 0; }
    have sudo || { printf 'none'; return 0; }

    _caps_capped 5 sudo -n true 2>/dev/null && { printf 'sudo'; return 0; }

    # sudo declined without a password. Two very different causes: a password is
    # required (recoverable, but only with a tty to ask on) or this user has no
    # sudo rights at all (not recoverable — don't pretend otherwise).
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

# sudo's default env_reset strips http_proxy/https_proxy/no_proxy, so behind a
# corporate proxy `sudo apt-get update` quietly loses its only route out and
# dies on a timeout with nothing in the log about proxies. `-E` keeps them —
# but sudoers can forbid -E, and then the command fails outright, so probe once
# rather than assuming either way. Cached (exported) like every other capability.
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
            # No way to probe this one without triggering the password prompt we
            # are trying not to trigger. Ask for -E and let sudo complain if it
            # objects — a visible refusal beats a silent proxy-less failure.
            sudo-interactive) ENVUP_PRIV_KEEP_ENV=1 ;;
        esac
    fi
fi

# The argv prefix that turns a command into a privileged one, as an array so it
# can be spliced into a command line. That splicing is the point: `timeout` can
# run a program but not a shell function, so the package-manager arrays in
# pkg.sh need a prefix they can embed, not a wrapper they must call.
# Empty when we are already root; also empty (and unusable) when ENVUP_PRIV=none,
# which is why callers must go through priv_run or check priv_available first.
ENVUP_PRIV_ARGV=()
case "$ENVUP_PRIV" in
    sudo)             ENVUP_PRIV_ARGV=(sudo -n) ;;
    sudo-interactive) ENVUP_PRIV_ARGV=(sudo) ;;
esac
if (( ${#ENVUP_PRIV_ARGV[@]} )) && (( ENVUP_PRIV_KEEP_ENV )); then ENVUP_PRIV_ARGV+=(-E); fi

priv_available() { [[ "$ENVUP_PRIV" == root || "$ENVUP_PRIV" == sudo || "$ENVUP_PRIV" == sudo-interactive ]]; }

# priv_run <cmd>... — run <cmd> as root. Refuses loudly when there is no route
# to root, rather than running it unprivileged and surfacing a confusing
# permission error from somewhere deep inside a package manager.
# Exit status 77 means "no privileges here" and nothing else; callers that have
# a user-space fallback can branch on it.
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

# Is $HOME shared with other machines? On a network home the same dotfiles are
# read by hosts with different tool paths, different hardware and different
# proxies, so anything machine-specific has to be keyed by hostname instead of
# just written into $HOME. It also explains slow shell startup (every compinit
# stat is a round trip) and is why link comparison must survive $HOME being
# reachable under two different paths.
_caps_home_shared() {
    local fs=""
    # GNU stat prints the filesystem type directly; BSD stat has no equivalent.
    fs="$(stat -f -c %T "$HOME" 2>/dev/null || echo "")"
    [[ -z "$fs" ]] && fs="$(df -PT "$HOME" 2>/dev/null | awk 'NR==2{print $2}')"
    case "$fs" in
        nfs*|cifs|smb*|autofs|afs|lustre|gpfs|beegfs|fuse.sshfs|fuse.glusterfs) printf 1; return 0 ;;
    esac
    # Fallback that works everywhere including macOS: a network mount's device
    # column is written host:/export.
    local dev; dev="$(df -P "$HOME" 2>/dev/null | awk 'NR==2{print $1}')"
    [[ "$dev" == *:/* ]] && { printf 1; return 0; }
    printf 0
}
ENVUP_HOME_SHARED="${ENVUP_HOME_SHARED:-$(_caps_home_shared)}"

# ---- network -------------------------------------------------------------
# Probed lazily: plenty of commands (status, doctor --authoring, uninstall) never
# touch the network, and they shouldn't pay for a round trip. The first caller
# probes; everyone after that, in this shell or any hook subshell, reads the
# exported answer.
#
#   direct   github.com is reachable
#   mirror   github.com is not, but ENVUP_GH_MIRROR is — rewrite and carry on
#   offline  neither; providers must skip network steps and say so
#
# ENVUP_OFFLINE=1 forces offline without probing, which is also the way to make
# a run reproducible on a machine whose connectivity flaps.
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
        # A configured mirror wins over a reachable github.com: the user set it
        # because the direct route is slow or filtered, not as a fallback.
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
# One line describing this machine, for logs, `envup status` and bug reports.
# ENVUP_PKG comes from pkg.sh, which loads after this file — read at call time.
caps_summary() {
    printf 'os=%s platform=%s distro=%s%s arch=%s libc=%s priv=%s pkg=%s host=%s shared_home=%s net=%s' \
        "$ENVUP_OS" "$ENVUP_PLATFORM" "$ENVUP_DISTRO" "${ENVUP_DISTRO_VER:+-$ENVUP_DISTRO_VER}" \
        "$ENVUP_ARCH" "$ENVUP_LIBC" "$ENVUP_PRIV" "${ENVUP_PKG:-unknown}" \
        "$ENVUP_HOST" "$ENVUP_HOME_SHARED" "${ENVUP_NET:-unprobed}"
}

export ENVUP_PLATFORM ENVUP_OS ENVUP_DISTRO ENVUP_DISTRO_VER ENVUP_DISTRO_LIKE
export ENVUP_ARCH ENVUP_ARCH_RAW ENVUP_LIBC
export ENVUP_PRIV ENVUP_PRIV_KEEP_ENV ENVUP_HOST ENVUP_HOME_SHARED
