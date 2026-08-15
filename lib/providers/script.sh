#!/bin/bash
# ============================================
# provider: script — the vendor's own curl | sh installer
# ============================================
# Last resort before giving up, because these scripts are the least predictable
# thing envup runs: they choose their own install prefix, they take as long as
# they take, and most of them append shell-init lines to whatever rc files they
# find. Two consequences are handled here rather than in each module:
#
#   the URL goes through net_fetch, so a mirror/proxy/offline machine gets the
#   same treatment as every other download (an installer invoked with a bare
#   curl is exactly how atuin used to slip past ENVUP_GH_MIRROR);
#
#   rc files that are envup symlinks are swapped aside for the duration. The
#   installer appends to a temporary empty file instead of dirtying a
#   version-controlled one in the repo — and the swap is undone by a trap, so
#   an interrupted install cannot leave you without a .zshrc.
#
# Depends on: engine.sh, net.sh, fs.sh
# ============================================

_script_shielded=()

_script_shield() {
    _script_shielded=()
    local f
    for f in "$HOME/.zshrc" "$HOME/.zshenv" "$HOME/.bashrc" "$HOME/.profile" "$HOME/.bash_profile"; do
        is_envup_link "$f" || continue
        mv "$f" "$f.envup-bak" && : >"$f" && _script_shielded+=("$f")
    done
}

_script_unshield() {
    local x
    for x in "${_script_shielded[@]+"${_script_shielded[@]}"}"; do
        [[ -e "$x.envup-bak" ]] || continue
        rm -f "$x"; mv "$x.envup-bak" "$x"
    done
    _script_shielded=()
}

# provider_script [url] — pipe the vendor installer into sh.
provider_script() {
    local url="${1:-$SCRIPT_URL}"
    [[ -n "$url" ]] || { log_error "[$NAME] script provider needs SCRIPT_URL"; return 1; }

    if [[ "${ENVUP_DRY_RUN:-0}" == 1 ]]; then
        log_info "[dry-run] would run the $NAME installer from $(gh_url "$url")"; return 0
    fi
    if ! have curl && ! have wget; then
        log_debug "[$NAME] no curl/wget for the vendor installer"
        return "$ENVUP_RC_UNAVAIL"
    fi
    if ! net_online; then
        log_debug "[$NAME] offline; cannot fetch the vendor installer"
        return "$ENVUP_RC_UNAVAIL"
    fi

    # Fetch first, then run. Downloading to a file rather than piping straight
    # into sh means a truncated transfer is a download error instead of half a
    # script executing — and it puts the script in the log directory, which is
    # the only way to find out afterwards what it actually did.
    local tmp; tmp="$(mktemp "${TMPDIR:-/tmp}/envup-$NAME-installer.XXXXXX")" || return 1
    if ! net_fetch "$url" "$tmp"; then
        rm -f "$tmp"
        log_error "[$NAME] could not download the installer from $(gh_url "$url")"
        return 1
    fi

    log_step "[$NAME] running the vendor installer"
    _script_shield
    trap '_script_unshield' EXIT INT TERM HUP
    net_run_logged "$NAME installer" -- sh "$tmp" ${SCRIPT_ARGS:+$SCRIPT_ARGS}
    local rc=$?
    _script_unshield
    trap - EXIT INT TERM HUP
    rm -f "$tmp"

    if (( rc != 0 )); then
        log_error "[$NAME] vendor installer failed (rc=$rc)"
        log_hint "slow link? raise the budget: ENVUP_NET_TIMEOUT_INSTALLER=600 envup install $NAME"
        return 1
    fi
    # Vendor installers love ~/.local/bin and ~/.<tool>/bin; make the freshly
    # installed binary visible to the verify step in this same process.
    export PATH="$ENVUP_LOCAL_BIN:$HOME/.$NAME/bin:$PATH"
}
