#!/bin/bash
# Update the checkout, then reinstall recorded modules through cmd_install.
# Managed links follow checkout changes immediately; source/provider failures
# must report the resulting revision rather than imply a complete rollback.
# Depends on: log.sh, net.sh, health.sh

# _upgrade_git — is $ENVUP_HOME something git can act on at all?
_upgrade_git() {
    have git || { log_error "git is not installed — envup upgrade cannot update the source"; return 1; }
    git -C "$ENVUP_HOME" rev-parse --git-dir >/dev/null 2>&1 && return 0
    log_error "$ENVUP_HOME is not a git checkout"
    log_hint "installed from an archive? re-clone it: git clone <url> $ENVUP_HOME"
    return 1
}

# _upgrade_branch — the branch name, or empty when HEAD is detached.
_upgrade_branch() { git -C "$ENVUP_HOME" symbolic-ref --short -q HEAD 2>/dev/null; }

# _upgrade_detached_note — the message for a detached HEAD, which is a certain
# failure for `git pull` and worth catching before spending the network budget
# on a fetch that cannot be used.
_upgrade_detached_note() {
    local at; at="$(git -C "$ENVUP_HOME" describe --tags --always 2>/dev/null)"
    log_error "HEAD is detached${at:+ at $at} — there is no branch to pull"
    log_hint "this is what 'envup upgrade --ref ${at:-<tag>}' leaves behind, by design"
    log_hint "back to the branch: envup upgrade --ref main"
}

# _upgrade_dirty — report uncommitted changes, most explainable cause first.
# Returns 0 when it printed something, 1 when the tree is clean.
_upgrade_dirty() {
    local -a drift=() other=()
    local line path n=0

    while IFS= read -r line; do [[ -n "$line" ]] && drift+=("${line#*$'\t'}"); done < <(health_drift)

    # Everything else that is modified or staged. Submodules move whenever a
    # plugin updates; that is expected state, not an obstacle worth naming.
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        path="${line:3}"
        [[ -f "$ENVUP_HOME/$path/.git" || -d "$ENVUP_HOME/$path/.git" ]] && continue
        printf '%s\n' "${drift[@]+"${drift[@]}"}" | grep -qxF "$path" && continue
        other+=("$path")
    done < <(git -C "$ENVUP_HOME" status --porcelain --untracked-files=no 2>/dev/null)

    (( ${#drift[@]} + ${#other[@]} )) || return 1

    if (( ${#drift[@]} )); then
        log_error "managed config files have been edited in place:"
        for path in "${drift[@]}"; do
            (( ++n > 5 )) && { log_error "  ... and $(( ${#drift[@]} - 5 )) more"; break; }
            log_error "  $path"
        done
        log_hint "these are the files your shell symlinks to, so something wrote through the link"
        log_hint "move the additions out and restore the repo: envup adopt"
    fi
    if (( ${#other[@]} )); then
        n=0
        log_error "the checkout has uncommitted changes:"
        for path in "${other[@]}"; do
            (( ++n > 5 )) && { log_error "  ... and $(( ${#other[@]} - 5 )) more"; break; }
            log_error "  $path"
        done
        log_hint "commit them, or set them aside: git -C $ENVUP_HOME stash"
    fi
    return 0
}

# _upgrade_why — everything envup knows about why the update just failed, in
# the order a person would check. git has already printed its own message; this
# says what it means for this repo.
_upgrade_why() {
    local branch upstream
    branch="$(_upgrade_branch)"

    if [[ -z "$branch" ]]; then _upgrade_detached_note; return 0; fi
    if _upgrade_dirty; then return 0; fi

    if ! upstream="$(git -C "$ENVUP_HOME" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)" ||
       [[ -z "$upstream" ]]; then
        log_error "branch '$branch' is not tracking anything — git has nowhere to pull from"
        log_hint "git -C $ENVUP_HOME branch --set-upstream-to=origin/$branch $branch"
        return 0
    fi

    if [[ "${ENVUP_NET:-}" == offline ]]; then
        log_error "no route to the network — the source cannot be updated here"
        return 0
    fi

    log_error "git could not update '$branch' from $upstream — its message is above"
    log_hint "check it by hand: git -C $ENVUP_HOME status && git -C $ENVUP_HOME pull"
    return 0
}

# A submodule failure can occur after HEAD changed; report the actual checkout.
_upgrade_source_result() {
    local before="$1" after
    after="$(git -C "$ENVUP_HOME" rev-parse HEAD 2>/dev/null)" || after=unknown
    if [[ "${2:-}" == success ]]; then log_info "source checkout: $after"; return 0; fi
    if [[ "$before" == "$after" ]]; then
        log_info "source HEAD unchanged at $after; submodule changes were not rolled back"
    else
        log_warn "source HEAD changed: $before -> $after; checkout changes were not rolled back"
    fi
}

# upgrade_source [ref] — move the checkout forward. 0 on success, 1 on failure
# with the reason already reported. Honours ENVUP_DRY_RUN.
upgrade_source() {
    local ref="${1:-}"

    if [[ "${ENVUP_DRY_RUN:-0}" == 1 ]]; then
        if [[ -n "$ref" ]]; then log_info "[dry-run] would: git fetch --tags && git checkout $ref (+submodules)"
        else log_info "[dry-run] would: git pull --ff-only --recurse-submodules"; fi
        return 0
    fi

    _upgrade_git || return 1
    local before; before="$(git -C "$ENVUP_HOME" rev-parse HEAD)" || return 1

    if [[ -n "$ref" ]]; then
        if ! ( cd "$ENVUP_HOME" && net_run "git fetch" -- git fetch --tags --recurse-submodules ); then
            log_error "fetch for '$ref' failed"
            _upgrade_source_result "$before"; return 1
        fi
        if ! git -C "$ENVUP_HOME" checkout "$ref"; then
            log_error "checkout of '$ref' failed"
            _upgrade_dirty || {
                log_error "no tag or branch called '$ref'"
                log_hint "what is available: git -C $ENVUP_HOME tag; git -C $ENVUP_HOME branch -r"
            }
            _upgrade_source_result "$before"; return 1
        fi
        if ! ( cd "$ENVUP_HOME" && net_run "git submodule update" -- git submodule update --init --recursive ); then
            log_error "submodule update for '$ref' failed"
            _upgrade_source_result "$before"; return 1
        fi
        _upgrade_source_result "$before" success; return 0
    fi

    # A detached HEAD cannot be pulled into, so say so instead of spending the
    # network timeout finding out.
    [[ -n "$(_upgrade_branch)" ]] || { _upgrade_detached_note; return 1; }

    if ( cd "$ENVUP_HOME" && net_run "git pull" -- git pull --ff-only --recurse-submodules ); then
        _upgrade_source_result "$before" success; return 0
    fi
    log_error "git pull failed"
    _upgrade_why
    _upgrade_source_result "$before"
    return 1
}
