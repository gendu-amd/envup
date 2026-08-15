#!/bin/bash
# ============================================
# envup — the install engine
# ============================================
# A module used to be a shell script that installed itself. Every one of them
# re-implemented the same sequence — try the package manager, else curl | sh,
# then symlink some files — and each one got a slightly different subset of it
# right. None of them had a path that works without root, because writing that
# path seven times was never going to happen.
#
# So meta.sh is now data and this file is the only implementation:
#
#   pre_install          module hook, optional
#   tool                 walk PROVIDERS until VERIFY_BIN is present + new enough
#   links                LINKS -> safe_link (backup-never-clobber still applies)
#   post_install         module hook, optional
#   verify               VERIFY_BIN resolves and meets VERIFY_MIN_VERSION
#
# The result is one of four states, never a bare pass/fail:
#   ok         the tool is there and the config is linked
#   degraded   the config is linked but the tool could not be installed here
#              (no root and nothing user-space to fall back to). This is the
#              normal outcome for zsh/git/tmux on a locked-down server, and it
#              is NOT a failure: the config lands, and the day an admin installs
#              the package everything works with no further action.
#   skipped    the module does not apply to this machine
#   failed     something that should have worked didn't
#
# Depends on: log.sh, caps.sh, fs.sh, net.sh, pkg.sh, module.sh
# ============================================

# Result codes. These travel out through the watchdog child's exit status, so
# they have to be small integers that `timeout` doesn't already use (124/137/143).
ENVUP_RC_DEGRADED=70
ENVUP_RC_SKIPPED=71
# A provider returns this to mean "not me" — the route doesn't exist on this
# machine at all (no package for this distro, no release asset for this arch).
# Distinct from a real failure: it isn't worth a warning, just move on.
ENVUP_RC_UNAVAIL=79

# Where user-space installs go. Everything root-free lands here.
ENVUP_LOCAL_BIN="${ENVUP_LOCAL_BIN:-$HOME/.local/bin}"

# ---- module metadata -----------------------------------------------------
# _engine_load <mod> — source meta.sh (+ optional hooks.sh) and give every
# field a defined value. Fields are globals so providers and hooks can read
# them without being handed twelve arguments.
# shellcheck disable=SC2034  # the whole contract is read by providers and hooks
_engine_load() {
    local mod="$1" dir="$ENVUP_HOME/modules/$1"
    NAME="$mod"; DESCRIPTION=""; DEPENDS=(); SELF_DEPS=()
    PROVIDERS=(); PKG_NAMES=(); PKG_DEFAULT=""
    GH_REPO=""; GH_BIN=""; GH_ASSET=""; GH_STRIP=""
    GIT_URL=""; GIT_DEST=""; SCRIPT_URL=""; MANUAL_HINT=""
    VERIFY_BIN=""; VERIFY_MIN_VERSION=""; VERIFY_VERSION_ARG="--version"
    LINKS=(); CLEAN_PATHS=(); APPLIES_IF=""
    # A hook sets this alongside a ENVUP_RC_DEGRADED return to say why.
    _ENG_HOOK_REASON=""
    # Which route actually worked, for the manifest.
    _ENG_PROVIDER=""

    # A hook left behind by a previously loaded module would silently run for
    # this one. envup installs modules sequentially in one process, so this is
    # not hypothetical.
    unset -f pre_install post_install pre_uninstall post_uninstall verify

    [[ -f "$dir/meta.sh" ]] || { log_error "[$mod] no meta.sh"; return 1; }
    # shellcheck source=/dev/null
    source "$dir/meta.sh" || { log_error "[$mod] meta.sh failed to load"; return 1; }
    if [[ -f "$dir/hooks.sh" ]]; then
        # shellcheck source=/dev/null
        source "$dir/hooks.sh" || { log_error "[$mod] hooks.sh failed to load"; return 1; }
    fi
}

# pkg_name — the name this module's package goes by on this machine's packaging
# tradition. fd is fd-find on Debian and fd on brew; without this table the
# system provider "works" everywhere except where it matters.
pkg_name() {
    local fam entry; fam="$(pkg_family)"
    for entry in "${PKG_NAMES[@]+"${PKG_NAMES[@]}"}"; do
        [[ "${entry%%:*}" == "$fam" ]] && { printf '%s' "${entry#*:}"; return 0; }
    done
    printf '%s' "${PKG_DEFAULT:-$NAME}"
}

# ---- verification --------------------------------------------------------
# bin_path <name> — where this binary actually is, including the user-space dir
# that may not be on PATH yet in this process (we just created it).
bin_path() {
    local b="$1" p
    p="$(command -v "$b" 2>/dev/null)" && { printf '%s' "$p"; return 0; }
    [[ -x "$ENVUP_LOCAL_BIN/$b" ]] && { printf '%s' "$ENVUP_LOCAL_BIN/$b"; return 0; }
    return 1
}

# bin_runs <name> — does this binary actually execute on this machine? Being on
# PATH and +x is not the same thing: a prebuilt binary linked against a newer
# glibc than the host has gets installed happily and then dies on every call
# with "version `GLIBC_2.33' not found". Asking it for its version is the
# cheapest way to make it prove itself.
bin_runs() {
    local p; p="$(bin_path "$1")" || return 1
    # Unquoted on purpose: a module may need more than one word ("version -q").
    # shellcheck disable=SC2086
    "$p" ${VERIFY_VERSION_ARG:---version} >/dev/null 2>&1
}

# bin_version <name> — first dotted number the tool prints. Deliberately loose
# about the format (every tool differs and we only ever compare it), strict
# about two things:
#
#   - a non-zero exit means no answer. Scraping the failure message above gave
#     nvim a confident "2.33" and a green tick for a binary that cannot start.
#   - stdout first. stderr is read only after a clean exit, for the few tools
#     that print their banner there, so a warning can never become a version.
bin_version() {
    local p; p="$(bin_path "$1")" || return 1
    local v out
    # shellcheck disable=SC2086
    out="$("$p" ${VERIFY_VERSION_ARG:---version} 2>/dev/null)" || return 1
    v="$(printf '%s\n' "$out" | head -3 | grep -oE '[0-9]+(\.[0-9]+)+' | head -1)"
    # shellcheck disable=SC2086
    [[ -n "$v" ]] || v="$("$p" ${VERIFY_VERSION_ARG:---version} 2>&1 >/dev/null |
        head -3 | grep -oE '[0-9]+(\.[0-9]+)+' | head -1)"
    [[ -n "$v" ]] || return 1
    printf '%s' "$v"
}

# version_ge <have> <want> — true when <have> is at least <want>.
version_ge() {
    [[ "$1" == "$2" ]] && return 0
    [[ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -1)" == "$2" ]]
}

# engine_verify — is the tool present and good enough? A module may replace this
# wholesale by defining verify() in hooks.sh.
engine_verify() {
    declare -F verify >/dev/null && { verify; return $?; }
    [[ -n "$VERIFY_BIN" ]] || return 0
    bin_path "$VERIFY_BIN" >/dev/null || return 1
    # Present is not the same as working. A module whose tool has no --version
    # (or answers on a flag envup cannot guess) sets VERIFY_VERSION_ARG, or
    # replaces this check wholesale with verify() in hooks.sh.
    bin_runs "$VERIFY_BIN" || return 1
    [[ -n "$VERIFY_MIN_VERSION" ]] || return 0
    local v; v="$(bin_version "$VERIFY_BIN")" || return 1
    version_ge "$v" "$VERIFY_MIN_VERSION"
}

# ---- providers -----------------------------------------------------------
# provider_run <spec> — "kind" or "kind:argument". The argument is a shorthand
# for the matching meta.sh field, so `github_release:cli/cli` and
# GH_REPO="cli/cli" mean the same thing.
provider_run() {
    local spec="$1" kind arg
    kind="${spec%%:*}"; arg="${spec#*:}"; [[ "$arg" == "$spec" ]] && arg=""
    case "$kind" in
        system)         provider_system         "$arg" ;;
        github_release) provider_github_release "$arg" ;;
        git)            provider_git            "$arg" ;;
        script)         provider_script         "$arg" ;;
        manual)         provider_manual         "$arg" ;;
        *) log_error "[$NAME] unknown provider '$kind' in meta.sh"; return 1 ;;
    esac
}

# _engine_tool — get VERIFY_BIN onto this machine. Returns 0 ok / 70 degraded /
# 1 failed, and leaves a human sentence in _ENG_REASON either way.
_engine_tool() {
    _ENG_REASON=""
    [[ -n "$VERIFY_BIN" ]] || { _ENG_REASON="config only"; return 0; }

    if engine_verify; then
        _ENG_REASON="$VERIFY_BIN $(bin_version "$VERIFY_BIN" || echo present) already installed"
        _ENG_PROVIDER="preinstalled"
        return 0
    fi

    # Present but too old, present but unrunnable, and absent all read very
    # differently. Conflating the first two is how "nvim too old: " (with an
    # empty version) used to happen.
    local had=""
    if bin_path "$VERIFY_BIN" >/dev/null; then
        if ! bin_runs "$VERIFY_BIN"; then
            log_warn "[$NAME] $VERIFY_BIN is installed but will not run here" \
                     "(wrong libc or arch?) — looking for another route"
        elif [[ -n "$VERIFY_MIN_VERSION" ]]; then
            had="$(bin_version "$VERIFY_BIN" || echo unknown)"
            log_info "[$NAME] $VERIFY_BIN $had is older than the required $VERIFY_MIN_VERSION"
        fi
    fi

    if (( ${#PROVIDERS[@]} == 0 )); then
        _ENG_REASON="no way to install $VERIFY_BIN is declared in meta.sh"
        return "$ENVUP_RC_DEGRADED"
    fi

    if [[ "${ENVUP_DRY_RUN:-0}" == 1 ]]; then
        # A preview must not install, and must not then judge the machine for
        # not having installed anything. It reports the plan and stops.
        log_info "[dry-run] would install $VERIFY_BIN via: ${PROVIDERS[*]}"
        _ENG_REASON="[dry-run] not installed"
        return 0
    fi

    local p rc tried=0
    for p in "${PROVIDERS[@]}"; do
        provider_run "$p"; rc=$?
        if (( rc == 0 )); then
            if engine_verify; then
                _ENG_REASON="installed via ${p%%:*}"
                _ENG_PROVIDER="${p%%:*}"
                return 0
            fi
            log_warn "[$NAME] ${p%%:*} reported success but $VERIFY_BIN still does not check out"
            rc=1
        fi
        if (( rc == ENVUP_RC_DEGRADED )); then
            # A provider that returns 'degraded' has settled the question — it
            # is the manual one, saying a human has to do this. Nothing after it
            # in the chain can do better.
            _ENG_REASON="$VERIFY_BIN must be installed by hand here"
            return "$ENVUP_RC_DEGRADED"
        fi
        if (( rc == ENVUP_RC_UNAVAIL )); then
            log_debug "[$NAME] provider ${p%%:*} does not apply here"
        else
            tried=1
            log_warn "[$NAME] provider ${p%%:*} failed (rc=$rc)"
        fi
    done

    # Nothing worked. That is only a failure if some route should have worked;
    # on a no-root server with no release asset for this arch it is just the
    # truth about the machine, and the config still gets linked.
    if (( tried )); then
        _ENG_REASON="every provider failed (${PROVIDERS[*]})"
    else
        _ENG_REASON="no usable install route on this machine (${PROVIDERS[*]})"
    fi
    [[ -n "$had" ]] && _ENG_REASON="$_ENG_REASON; keeping $VERIFY_BIN $had"
    return "$ENVUP_RC_DEGRADED"
}

# ---- links ---------------------------------------------------------------
# LINKS entries are "<repo-relative source>:<absolute destination>". A leading
# '?' marks the source as optional (missing is a warning, not an error) — used
# for submodule content that may not be checked out.
_engine_links() {
    local entry src dst opt rc=0
    for entry in "${LINKS[@]+"${LINKS[@]}"}"; do
        [[ -n "$entry" ]] || continue
        opt=0; [[ "$entry" == '?'* ]] && { opt=1; entry="${entry#\?}"; }
        src="${entry%%:*}"; dst="${entry#*:}"
        if [[ "$src" == "$dst" || -z "$src" || -z "$dst" ]]; then
            log_error "[$NAME] malformed LINKS entry (want 'src:dst'): $entry"; rc=1; continue
        fi
        if (( opt )); then safe_link_optional "$src" "$dst" || rc=1
        else                safe_link          "$src" "$dst" || rc=1; fi
    done
    return $rc
}

_engine_unlinks() {
    local i entry dst
    for (( i = ${#LINKS[@]} - 1; i >= 0; i-- )); do
        entry="${LINKS[i]#\?}"
        dst="${entry#*:}"; [[ "$dst" == "$entry" ]] && continue
        unlink_safe "$dst"
    done
    return 0
}

_engine_hook() {
    declare -F "$1" >/dev/null || return 0
    log_debug "[$NAME] hook: $1"
    "$1"
}

# _engine_record <state> — write the manifest row. Done here rather than in the
# CLI because this is the only place that knows *which* provider worked and what
# version landed, and those are exactly the two things you want when the same
# module behaves differently on two machines.
_engine_record() {
    [[ "${ENVUP_DRY_RUN:-0}" == 1 ]] && return 0
    local ver=""
    [[ -n "$VERIFY_BIN" ]] && ver="$(bin_version "$VERIFY_BIN" 2>/dev/null)"
    manifest_record "$NAME" "$1" "$_ENG_PROVIDER" "$ver"
}

# ---- the two entry points ------------------------------------------------
engine_install() {
    local mod="$1"
    _engine_load "$mod" || return 1

    # APPLIES_IF is a shell condition; a module that doesn't belong on this
    # machine says so itself rather than failing halfway through.
    if [[ -n "$APPLIES_IF" ]] && ! eval "$APPLIES_IF"; then
        log_info "[$mod] does not apply here ($APPLIES_IF)"
        return "$ENVUP_RC_SKIPPED"
    fi

    _engine_hook pre_install || { log_error "[$mod] pre_install failed"; return 1; }

    _engine_tool; local tool=$?
    (( tool == 1 )) && { log_error "[$mod] $_ENG_REASON"; return 1; }
    log_info "[$mod] tool: $_ENG_REASON"
    # Remembered separately from `tool`, which a hook may overwrite below: the
    # "it works once the binary exists" hint is only true when the binary is
    # what is missing.
    local tool_missing=$(( tool == ENVUP_RC_DEGRADED ))

    # Config is linked whatever happened to the tool. That is what makes
    # 'degraded' worth having: the machine is left correctly configured, so the
    # moment the binary appears it just works.
    _engine_links || { log_error "[$mod] linking failed"; return 1; }

    # A hook may return ENVUP_RC_DEGRADED to mean "I did what I could, and the
    # module is usable but incomplete" — nvim with no git to clone plugins with,
    # for instance. Failing the module there would be wrong: the editor and its
    # config are installed and working.
    _engine_hook post_install; local ph=$?
    if (( ph == ENVUP_RC_DEGRADED )); then
        tool="$ENVUP_RC_DEGRADED"
        _ENG_REASON="${_ENG_HOOK_REASON:-post_install could not finish everything}"
    elif (( ph != 0 )); then
        log_error "[$mod] post_install failed"; return 1
    fi

    if (( tool == ENVUP_RC_DEGRADED )); then
        log_warn "[$mod] degraded: $_ENG_REASON"
        (( tool_missing )) && [[ -n "$VERIFY_BIN" ]] &&
            log_hint "the config is linked — it works as soon as $VERIFY_BIN exists"
        _engine_record degraded
        return "$ENVUP_RC_DEGRADED"
    fi
    _engine_record ok
    return 0
}

engine_uninstall() {
    local mod="$1"
    _engine_load "$mod" || return 1
    _engine_hook pre_uninstall || { log_error "[$mod] pre_uninstall failed"; return 1; }
    _engine_unlinks
    _engine_hook post_uninstall || { log_error "[$mod] post_uninstall failed"; return 1; }
    # Binaries are never removed: envup did not necessarily install them, and
    # on a shared machine it certainly isn't envup's call.
    [[ -n "$VERIFY_BIN" ]] && log_info "[$mod] $VERIFY_BIN left installed (envup only removes its own symlinks)"
    return 0
}

# engine_state_label <rc> — one word for the result table.
engine_state_label() {
    case "$1" in
        0)                     echo ok ;;
        "$ENVUP_RC_DEGRADED")  echo degraded ;;
        "$ENVUP_RC_SKIPPED")   echo skipped ;;
        124|137|143)           echo timeout ;;
        *)                     echo failed ;;
    esac
}
