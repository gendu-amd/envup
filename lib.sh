#!/bin/bash
# ============================================
# envup shared library — one file, sourced by the CLI and by module hooks.
# ============================================
# Everything the tool needs in one place. Module hooks
# (modules/<name>/{install,uninstall}.sh) run in a subshell that inherits these
# functions — they just call safe_link / pkg_install / log_* / etc.
#
# Section contract (keep this order; each section is a "# ---- NAME ----" band):
#   logging  ·  platform + package manager  ·  safe symlink  ·  managed block
#   ·  network with timeout  ·  git submodule plugins  ·  manifest
#   ·  modules + profiles  ·  module hook runner
# This file is intentionally single-file and small. If it grows past ~400 lines,
# split a cohesive section into lib/<name>.sh and source it here (see
# docs/ARCHITECTURE.md "lib.sh sections"). The lint script warns past that size.
# ============================================

# ---- logging -------------------------------------------------------------
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

have() { command -v "$1" &>/dev/null; }
pkg_have() { command -v "$1" &>/dev/null; }

# ---- platform + package manager -----------------------------------------
# Canonical platform-detection rule (see docs/ARCHITECTURE.md "Platform
# detection"). Kept identical to modules/zsh/files/.zshrc.d/platform.zsh so the
# install-time (bash) and runtime (zsh) verdicts never drift:
#   Darwin -> macos; Linux+microsoft -> wsl2; Linux+(dockerenv|cgroup) -> docker;
#   Linux -> linux; anything else -> linux (fallback).
case "$(uname -s)" in
    Darwin) ENVUP_PLATFORM=macos ;;
    Linux)  if grep -qi microsoft /proc/version 2>/dev/null; then ENVUP_PLATFORM=wsl2
            elif [[ -f /.dockerenv ]] || grep -q 'docker\|containerd' /proc/1/cgroup 2>/dev/null; then ENVUP_PLATFORM=docker
            else ENVUP_PLATFORM=linux; fi ;;
    *)      ENVUP_PLATFORM=linux ;;
esac
ENVUP_ARCH=$(uname -m)
_sudo=""; [[ $EUID -ne 0 ]] && have sudo && _sudo=sudo
if   have apt-get; then ENVUP_PKG=apt;    _PKG_INSTALL=(${_sudo:+$_sudo} apt-get install -y);    _PKG_UPDATE=(${_sudo:+$_sudo} apt-get update)
elif have dnf;     then ENVUP_PKG=dnf;    _PKG_INSTALL=(${_sudo:+$_sudo} dnf install -y);         _PKG_UPDATE=(${_sudo:+$_sudo} dnf makecache)
elif have yum;     then ENVUP_PKG=yum;    _PKG_INSTALL=(${_sudo:+$_sudo} yum install -y);         _PKG_UPDATE=(${_sudo:+$_sudo} yum makecache)
elif have pacman;  then ENVUP_PKG=pacman; _PKG_INSTALL=(${_sudo:+$_sudo} pacman -S --noconfirm);  _PKG_UPDATE=(${_sudo:+$_sudo} pacman -Sy)
elif have brew;    then ENVUP_PKG=brew;   _PKG_INSTALL=(brew install);                            _PKG_UPDATE=(brew update)
elif have apk;     then ENVUP_PKG=apk;    _PKG_INSTALL=(${_sudo:+$_sudo} apk add --no-cache);     _PKG_UPDATE=(${_sudo:+$_sudo} apk update)
else                    ENVUP_PKG=unknown; _PKG_INSTALL=();                                        _PKG_UPDATE=()
fi
# Exported so module hooks (run in subshells by run_module_hook) and `envup
# status` can read the detected platform/arch/pkg-manager.
export ENVUP_PLATFORM ENVUP_ARCH ENVUP_PKG

_pkg_updated="${_pkg_updated:-0}"   # inherit "already refreshed" across hook subshells
# Install system packages. Output flows to the terminal (sudo prompts visible)
# and is tee'd to the log. Honours ENVUP_DRY_RUN. Lazy `update` on first use.
pkg_install() {
    [[ $# -eq 0 ]] && return 0
    if [[ ${#_PKG_INSTALL[@]} -eq 0 ]]; then
        log_error "no supported package manager (apt/dnf/yum/pacman/brew/apk)"
        log_hint "install manually: $*"; return 1
    fi
    if [[ "${ENVUP_DRY_RUN:-0}" == 1 ]]; then log_info "[dry-run] ${_PKG_INSTALL[*]} $*"; return 0; fi
    # Wrap the package manager in a timeout too — a stuck mirror or repo lock
    # must not hang the whole run (see run_module_hook's watchdog).
    local t; t=$(_net_timeout_bin); local ib="$ENVUP_NET_TIMEOUT_INSTALLER"
    if [[ $_pkg_updated == 0 && ${#_PKG_UPDATE[@]} -gt 0 ]]; then
        log_info "refreshing package lists"
        if [[ -n "$t" ]]; then "$t" -k "$ENVUP_NET_KILL_AFTER" "$ib" "${_PKG_UPDATE[@]}" 2>&1 | tee -a "$ENVUP_LOG_FILE"
        else "${_PKG_UPDATE[@]}" 2>&1 | tee -a "$ENVUP_LOG_FILE"; fi
        _pkg_updated=1; export _pkg_updated
    fi
    log_info "installing: $*"
    if [[ -n "$t" ]]; then "$t" -k "$ENVUP_NET_KILL_AFTER" "$ib" "${_PKG_INSTALL[@]}" "$@" 2>&1 | tee -a "$ENVUP_LOG_FILE"
    else "${_PKG_INSTALL[@]}" "$@" 2>&1 | tee -a "$ENVUP_LOG_FILE"; fi   # pipefail -> install's rc
}

# ---- safe symlink (always backs up a pre-existing real file) -------------
ENVUP_BACKUP_DIR="${ENVUP_BACKUP_DIR:-$HOME/.dotfiles_backup/$(date +%Y%m%d_%H%M%S)}"
safe_link()          { _link "$1" "$2" required; }
safe_link_optional() { _link "$1" "$2" optional; }
_link() {
    local src="$1" dst="$2" mode="${3:-required}"
    [[ "$src" != /* ]] && src="$ENVUP_HOME/$src"
    if [[ ! -e "$src" ]]; then
        [[ "$mode" == optional ]] && { log_warn "skip optional (missing): $src"; return 0; }
        log_error "source not found: $src"; log_hint "did you 'git clone --recursive'?"; return 1
    fi
    if [[ -L "$dst" && "$(readlink -f "$dst" 2>/dev/null || readlink "$dst")" == "$(readlink -f "$src" 2>/dev/null || echo "$src")" ]]; then
        log_info "already linked: $dst"; return 0
    fi
    if [[ "${ENVUP_DRY_RUN:-0}" == 1 ]]; then log_info "[dry-run] link $dst -> $src"; return 0; fi
    if [[ -e "$dst" && ! -L "$dst" ]]; then            # back up a real file/dir
        mkdir -p "$ENVUP_BACKUP_DIR"
        mv "$dst" "$ENVUP_BACKUP_DIR/" || { log_error "backup failed: $dst"; return 1; }
        log_info "backup: $dst -> $ENVUP_BACKUP_DIR/"
    fi
    [[ -L "$dst" ]] && rm -f "$dst"
    mkdir -p "$(dirname "$dst")"
    ln -sf "$src" "$dst" && log_success "linked: $dst"
}
# ---- managed text block (for files we append to but don't own, e.g. ~/.bashrc)
# block_set <file> <tag> : insert/replace a marker-delimited block; content on
# stdin. block_del <file> <tag> : remove it. Idempotent + dry-run aware. The
# `-i.bak` form is portable across GNU and BSD sed (macOS).
_block_markers() { _BLK_BEGIN="# >>> envup:$1 >>>"; _BLK_END="# <<< envup:$1 <<<"; }
block_set() {
    local file="$1" tag="$2" content; content="$(cat)"
    _block_markers "$tag"
    if [[ "${ENVUP_DRY_RUN:-0}" == 1 ]]; then log_info "[dry-run] update '$tag' block in $file"; return 0; fi
    mkdir -p "$(dirname "$file")"; touch "$file"
    block_del "$file" "$tag"
    printf '%s\n%s\n%s\n' "$_BLK_BEGIN" "$content" "$_BLK_END" >>"$file"
}
block_del() {
    local file="$1" tag="$2"; [[ -f "$file" ]] || return 0
    _block_markers "$tag"
    if [[ "${ENVUP_DRY_RUN:-0}" == 1 ]]; then log_info "[dry-run] remove '$tag' block from $file"; return 0; fi
    grep -qF "$_BLK_BEGIN" "$file" || return 0
    sed -i.envup-bak "\|^${_BLK_BEGIN}\$|,\|^${_BLK_END}\$|d" "$file" && rm -f "$file.envup-bak"
}

is_envup_link() { [[ -L "$1" ]] && [[ "$(readlink -f "$1" 2>/dev/null || readlink "$1")" == "$ENVUP_HOME"/* ]]; }
unlink_safe() {
    local dst="$1"
    is_envup_link "$dst" || { log_info "skip (not an envup link): $dst"; return 0; }
    if [[ "${ENVUP_DRY_RUN:-0}" == 1 ]]; then log_info "[dry-run] rm $dst"; return 0; fi
    rm -f "$dst" && log_success "unlinked: $dst"
}

# ---- network with timeout ------------------------------------------------
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
_net_timeout_bin() { if have timeout; then echo timeout; elif have gtimeout; then echo gtimeout; fi; }
# net_run [--timeout N] "<desc>" -- <cmd>...    (output to terminal)
net_run() {
    local budget="$ENVUP_NET_TIMEOUT"
    [[ "$1" == --timeout ]] && { budget="$2"; shift 2; }
    local desc="$1"; shift; [[ "$1" == -- ]] && shift
    local t; t=$(_net_timeout_bin)
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
    local t; t=$(_net_timeout_bin)
    log_info "$desc (${budget}s timeout)"
    if [[ -n "$t" ]]; then "$t" -k "$ENVUP_NET_KILL_AFTER" "$budget" "$@" >>"${ENVUP_LOG_FILE:-/dev/stderr}" 2>&1
    else "$@" >>"${ENVUP_LOG_FILE:-/dev/stderr}" 2>&1; fi
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

# ---- manifest (plain text, one module per line) --------------------------
# Format: a `# envup-manifest schema=N` header line followed by one module name
# per line. Comment lines (starting with #) are ignored on read, so old
# headerless manifests remain fully readable (backward compatible).
ENVUP_STATE_DIR="${ENVUP_STATE_DIR:-$HOME/.local/state/envup}"
ENVUP_MANIFEST="$ENVUP_STATE_DIR/installed"
ENVUP_MANIFEST_SCHEMA=1
_manifest_ensure() {
    mkdir -p "$ENVUP_STATE_DIR"
    [[ -f "$ENVUP_MANIFEST" ]] || printf '# envup-manifest schema=%s\n' "$ENVUP_MANIFEST_SCHEMA" >"$ENVUP_MANIFEST"
}
manifest_add()    { _manifest_ensure; grep -qxF "$1" "$ENVUP_MANIFEST" 2>/dev/null || echo "$1" >>"$ENVUP_MANIFEST"; }
manifest_remove() { [[ -f "$ENVUP_MANIFEST" ]] || return 0; grep -vxF "$1" "$ENVUP_MANIFEST" >"$ENVUP_MANIFEST.tmp" 2>/dev/null || true; mv -f "$ENVUP_MANIFEST.tmp" "$ENVUP_MANIFEST"; }
manifest_has()    { [[ -f "$ENVUP_MANIFEST" ]] && grep -qxF "$1" "$ENVUP_MANIFEST"; }
manifest_list()   { [[ -f "$ENVUP_MANIFEST" ]] || return 0; grep -v '^#' "$ENVUP_MANIFEST" 2>/dev/null || true; }

# ---- modules + profiles --------------------------------------------------
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

# Run a module hook in a subshell (inherits these helpers + env).
#
# Watchdog: the hook runs under an outer `timeout` so that NO single module can
# wedge the whole (sequential) run — regardless of what it does inside (a stuck
# pkg manager, a forgotten net_run, a step waiting on stdin). On timeout the
# module is reported as failed and cmd_install moves on to the next one.
#
# The timed child is a fresh bash, so it re-sources lib.sh to get every helper
# back (functions AND the pkg-manager arrays, which cannot be exported). $HOME,
# $ENVUP_HOME, $ENVUP_LOG_FILE, $ENVUP_BACKUP_DIR etc. are already exported.
run_module_hook() {
    local mod="$1" hook="$2" script="$ENVUP_HOME/modules/$1/$2.sh"
    [[ -f "$script" ]] || { log_warn "[$mod] no $hook.sh"; return 0; }
    log_step "[$mod] $hook"

    local t; t=$(_net_timeout_bin)
    if [[ -z "$t" || "${ENVUP_DRY_RUN:-0}" == 1 ]]; then
        # No timeout binary (warn once) or dry-run: run in-process as before.
        if [[ -z "$t" && -z "${_ENVUP_TIMEOUT_WARNED:-}" ]]; then
            log_warn "no 'timeout' binary — module hooks run without a watchdog (macOS: brew install coreutils)"
            _ENVUP_TIMEOUT_WARNED=1
        fi
        ( cd "$ENVUP_HOME/modules/$mod" && source "$script" )
        return $?
    fi

    # shellcheck disable=SC2016  # $ENVUP_HOME/$1/$2 must expand inside the child bash, not now
    "$t" -k "$ENVUP_NET_KILL_AFTER" "$ENVUP_MODULE_TIMEOUT" \
        bash -c 'set -uo pipefail; source "$ENVUP_HOME/lib.sh"; cd "$1" && source "$2"' \
        _ "$ENVUP_HOME/modules/$mod" "$script"
    local rc=$?
    if (( rc == 124 || rc == 137 || rc == 143 )); then
        log_error "[$mod] $hook timed out after ${ENVUP_MODULE_TIMEOUT}s and was killed"
        log_hint "raise it: ENVUP_MODULE_TIMEOUT=1800 envup install $mod"
    fi
    return $rc
}
