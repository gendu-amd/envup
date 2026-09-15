#!/bin/bash
# ============================================
# provider: git — clone a repo that carries its own installer
# ============================================
# For tools distributed as a checkout rather than a binary (fzf being the one
# that matters here). The clone goes through net_clone, so the mirror, the
# proxy, the offline check and the timeout all apply — which is exactly what a
# hand-written `git clone` in a module hook used to miss.
#
# GIT_URL   what to clone           (or pass it as the provider argument)
# GIT_DEST  where                    (default ~/.<module>)
# GIT_SETUP a command to run inside the clone afterwards, if any
#
# Depends on: engine.sh, net.sh
# ============================================

provider_git() {
    local url="${1:-$GIT_URL}" dest="${GIT_DEST:-$HOME/.$NAME}"

    [[ -n "$url" ]] || { log_error "[$NAME] git provider needs GIT_URL"; return 1; }
    if ! have git; then
        log_debug "[$NAME] no git on PATH"
        return "$ENVUP_RC_UNAVAIL"
    fi
    if ! net_online; then
        log_debug "[$NAME] offline; cannot clone"
        return "$ENVUP_RC_UNAVAIL"
    fi

    net_clone "$url" "$dest" || return 1

    if [[ -n "${GIT_SETUP:-}" ]]; then
        [[ "${ENVUP_DRY_RUN:-0}" == 1 ]] && { log_info "[dry-run] would run in $dest: $GIT_SETUP"; return 0; }
        ( cd "$dest" && log_run "$NAME setup" -- bash -c "$GIT_SETUP" ) \
            || { log_error "[$NAME] setup step failed in $dest"; return 1; }
    fi

    # A checkout-installed tool puts its binary in <dest>/bin, which is not on
    # anyone's PATH. Link it next to every other user-space tool so the verify
    # step finds it and so the shell needs to know about one directory, not one
    # per tool.
    if [[ -n "${VERIFY_BIN:-}" && -x "$dest/bin/$VERIFY_BIN" ]]; then
        mkdir -p "$ENVUP_LOCAL_BIN"
        ln -sf "$dest/bin/$VERIFY_BIN" "$ENVUP_LOCAL_BIN/$VERIFY_BIN"
        export PATH="$ENVUP_LOCAL_BIN:$PATH"
    fi
    return 0
}
