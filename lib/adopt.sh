#!/bin/bash
# ============================================
# envup — `adopt`: get third-party edits back out of the repo
# ============================================
# Configs are symlinks into the repo. That is the feature — edit once, every
# machine follows — and it is the hazard: a tool that appends a couple of lines
# to ~/.zshrc is appending them to a tracked file in your dotfiles. Then
# `envup upgrade` fails its git pull, on a machine you were not touching, for a
# reason that has nothing to do with envup. (nvm's installer did precisely this
# to this repo, twice.)
#
# `envup adopt` moves those appended lines to where machine-local config belongs
# — ~/.zshrc.local, which 80-local.zsh sources and git never sees — and restores
# the repo file.
#
# It is deliberately narrow. It only handles a *pure append* to a tracked file:
# the committed content is still there, unchanged, with new lines after it. That
# is the exact signature of an installer, and it is the only shape that can be
# undone without guessing. Anything else — a real edit, a deletion, a new
# untracked file — is left alone and reported, because on those the user's
# judgement beats ours.
#
# Depends on: log.sh, fs.sh, manifest.sh, health.sh
# ============================================

# adopt_appended <repo-relative-path> — the text appended to a tracked file
# since HEAD. Returns 1 when the change is anything other than a pure append,
# which is also how doctor asks "does this look like a tool did it?".
adopt_appended() {
    local rel="$1" committed current extra
    have git || return 1
    committed="$(git -C "$ENVUP_HOME" show "HEAD:$rel" 2>/dev/null)" || return 1
    [[ -f "$ENVUP_HOME/$rel" ]] || return 1
    current="$(cat "$ENVUP_HOME/$rel")" || return 1

    # $(...) strips trailing newlines from both sides, so this compares content
    # and not the presence of a final newline.
    [[ "$current" == "$committed"* ]] || return 1
    extra="${current#"$committed"}"
    while [[ "$extra" == $'\n'* ]]; do extra="${extra#$'\n'}"; done
    [[ -n "${extra//[[:space:]]/}" ]] || return 1
    printf '%s\n' "$extra"
}

# _adopt_dest <repo-relative-path> <timestamp> — where the rescued lines go.
# zsh config has a real home for machine-local settings; for anything else there
# is nowhere obviously right, so the lines are parked in the state directory
# under their original name and the user is told where.
_adopt_dest() {
    case "$1" in
        modules/zsh/files/*) printf '%s' "$HOME/.zshrc.local" ;;
        *)                   printf '%s' "$ENVUP_STATE_DIR/adopted/$2/${1//\//_}" ;;
    esac
}

adopt_main() {
    local dry=0; local -a want=()
    while (($#)); do case "$1" in
        -n|--dry-run) dry=1; shift ;;
        -h|--help) cat <<'EOF'
Usage: envup adopt [-n] [PATH...]
  Move lines that something appended to a managed file out of the repo and into
  machine-local config (~/.zshrc.local), then restore the file from git.
  PATH...  restrict to these repo-relative paths (default: everything drifted)
  -n       show what would move, change nothing
EOF
            return 0 ;;
        -*) log_error "unknown option: $1"; return 1 ;;
        *)  want+=("$1"); shift ;;
    esac; done

    if ! have git || ! git -C "$ENVUP_HOME" rev-parse --git-dir >/dev/null 2>&1; then
        log_error "adopt needs $ENVUP_HOME to be a git checkout"; return 1
    fi

    # Moves content between files and runs `git checkout --`; that belongs in
    # the log alongside install and upgrade.
    log_init adopt

    local -a rows=(); mapfile -t rows < <(health_drift)
    if (( ${#rows[@]} == 0 )); then
        log_success "no drift: every managed file matches the repo"
        return 0
    fi

    local ts; ts="$(date +%Y%m%d_%H%M%S)"
    local row path extra dest n=0 left=0 w hit
    for row in "${rows[@]}"; do
        path="${row#*$'\t'}"
        if (( ${#want[@]} )); then
            hit=0
            for w in "${want[@]}"; do [[ "$w" == "$path" || "$w" == "$ENVUP_HOME/$path" ]] && hit=1; done
            (( hit )) || continue
        fi

        if ! extra="$(adopt_appended "$path")"; then
            log_warn "$path: not a plain append — left alone"
            log_hint "review it yourself: git -C $ENVUP_HOME diff -- $path"
            left=$((left + 1))
            continue
        fi

        dest="$(_adopt_dest "$path" "$ts")"
        if (( dry )); then
            log_info "[dry-run] $path: $(printf '%s\n' "$extra" | wc -l | tr -d ' ') line(s) -> $dest, then restore from git"
            n=$((n + 1)); continue
        fi

        mkdir -p "$(dirname "$dest")"
        {
            printf '\n# --- adopted by envup on %s, appended to %s ---\n' "$ts" "$path"
            printf '%s\n' "$extra"
        } >>"$dest" || { log_error "could not write $dest"; return 1; }

        if ! git -C "$ENVUP_HOME" checkout -- "$path"; then
            log_error "$path: saved to $dest but could not restore the file"
            log_hint "restore it by hand: git -C $ENVUP_HOME checkout -- $path"
            return 1
        fi
        log_success "$path: appended lines moved to $dest, file restored"
        n=$((n + 1))
    done

    echo
    (( n ))    && log_info "adopted $n file(s)"
    (( left )) && log_warn "$left file(s) need a human — see above"
    (( n || left )) || log_info "nothing matched"
    # Leaving files behind is a report, not a failure: they may well be your own
    # edits, and adopt refusing to touch them is the correct outcome.
    return 0
}
