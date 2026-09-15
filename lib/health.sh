#!/bin/bash
# ============================================
# envup — machine-state inspection (read-only)
# ============================================
# The manifest records what envup *did*. This file reports what is *true now* —
# a distinction that used to be missing, and it mattered: `status` printed a
# green tick for a module whose config the user had deleted by hand an hour
# earlier, because the manifest still had the line.
#
# Everything here is read-only and side-effect free. `doctor` uses it to decide
# what to repair, `status` uses it to decide what to print; neither of them owns
# the answer, so both agree by construction.
#
# Depends on: log.sh, fs.sh, manifest.sh, module.sh, engine.sh
# ============================================

# ---- one link ------------------------------------------------------------
# health_link_state <repo-relative-src> <dst> — one word for what is at <dst>:
#
#   ok       a symlink to <src>, and <src> exists
#   broken   ours, but dangling or pointing at the wrong place — the repo moved,
#            the source was renamed, or a second checkout took the link over
#   foreign  something else lives there: a real file, or a link we do not own.
#            Never touched without a backup, so it is reported, not assumed.
#   missing  nothing is there
health_link_state() {
    local src="$1" dst="$2"
    [[ "$src" != /* ]] && src="$ENVUP_HOME/$src"
    if [[ -L "$dst" ]]; then
        if [[ "$(readlink "$dst" 2>/dev/null)" == "$src" ]] || paths_same "$dst" "$src"; then
            # -e follows the link: false here means the target is gone.
            [[ -e "$dst" ]] && { echo ok; return 0; }
            echo broken; return 0
        fi
        is_envup_link "$dst" && { echo broken; return 0; }
        echo foreign; return 0
    fi
    [[ -e "$dst" ]] && { echo foreign; return 0; }
    echo missing
}

# ---- one module ----------------------------------------------------------
# health_probe <mod> — everything known about <mod> on this machine, as
# tab-separated records:
#
#   tool<TAB><ok|old|broken|missing|none><TAB><detail>
#   link<TAB><ok|broken|foreign|missing|skipped><TAB><dst><TAB><src>
#   state<TAB><ok|degraded|broken|absent>
#
# Runs in a subshell because it sources the module's meta.sh, and meta.sh from
# one module must not still be in scope when the next one is probed — the same
# reason run_module_hook forks.
health_probe() (
    local mod="$1"
    _engine_load "$mod" >/dev/null 2>&1 || { printf 'state\tunknown\n'; return 0; }

    local tool=none detail=""
    if [[ -n "$VERIFY_BIN" ]]; then
        if engine_verify; then
            tool=ok; detail="$(bin_version "$VERIFY_BIN" 2>/dev/null || echo present)"
        elif ! bin_path "$VERIFY_BIN" >/dev/null 2>&1; then
            tool=missing; detail="$VERIFY_BIN not found"
        elif ! bin_runs "$VERIFY_BIN"; then
            # On PATH, executable, and still unusable — the shape of a prebuilt
            # binary that wants a newer libc than this host has. Worth its own
            # word: "missing" would send you looking for an install that already
            # happened, and "ok" is what we used to say.
            tool=broken; detail="$VERIFY_BIN is installed but will not run here"
        else
            tool=old; detail="$(bin_version "$VERIFY_BIN" 2>/dev/null || echo unknown) < $VERIFY_MIN_VERSION"
        fi
    fi
    printf 'tool\t%s\t%s\n' "$tool" "$detail"

    local entry src dst opt st bad=0
    for entry in "${LINKS[@]+"${LINKS[@]}"}"; do
        [[ -n "$entry" ]] || continue
        opt=0; [[ "$entry" == '?'* ]] && { opt=1; entry="${entry#\?}"; }
        src="${entry%%:*}"; dst="${entry#*:}"
        [[ "$src" == "$dst" || -z "$src" || -z "$dst" ]] && continue
        st="$(health_link_state "$src" "$dst")"
        # An optional link whose source was never checked out is not a fault —
        # that is what the '?' means.
        (( opt )) && [[ "$st" == missing && ! -e "$ENVUP_HOME/$src" ]] && st=skipped
        printf 'link\t%s\t%s\t%s\n' "$st" "$dst" "$src"
        case "$st" in ok|skipped) ;; *) bad=1 ;; esac
    done

    local state
    if ! manifest_has "$mod";       then state=absent
    elif (( bad ));                 then state=broken
    elif [[ "$tool" == ok || "$tool" == none ]]; then state=ok
    else                                 state=degraded
    fi
    printf 'state\t%s\n' "$state"
)

# health_field <probe-output> <key> — the value column of the first record whose
# first column is <key>. Saves every caller writing the same awk.
health_field() { printf '%s\n' "$1" | awk -F'\t' -v k="$2" '$1 == k { print $2; exit }'; }

# health_records <probe-output> <key> — every record of that kind, key stripped.
health_records() { printf '%s\n' "$1" | awk -F'\t' -v k="$2" '$1 == k { sub(/^[^\t]*\t/, ""); print }'; }

# health_link_counts <probe-output> — "<not-linked-yet> <dangling> <in-the-way>",
# the three ways a declared link can fail to be a working link. Separate from
# the summary below because `status --json` reports the numbers and the terminal
# reports the sentence, and they must not be able to disagree.
health_link_counts() {
    local line st n_missing=0 n_broken=0 n_foreign=0
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        st="${line%%$'\t'*}"
        case "$st" in
            missing) n_missing=$((n_missing + 1)) ;;
            broken)  n_broken=$((n_broken + 1)) ;;
            foreign) n_foreign=$((n_foreign + 1)) ;;
        esac
    done < <(health_records "$1" link)
    printf '%s %s %s\n' "$n_missing" "$n_broken" "$n_foreign"
}

# health_link_summary <probe-output> — why this module reads '!', in the words
# of what is actually wrong with its links.
#
# `status` used to call all three states "N broken link(s)", which was a small
# inaccuracy with a large cost. The common case by far is a link the repo grew
# after this machine last installed — a new helper script, a new config file —
# and there is nothing broken about it: nobody has run `envup install` since.
# "Broken" sends you looking for damage. The other two states want different
# hands entirely: a dangling link means the source moved or the checkout did,
# and a foreign one means your own file is sitting where a link should go and
# envup will not touch it without your say-so.
health_link_summary() {
    local n_missing n_broken n_foreign
    read -r n_missing n_broken n_foreign < <(health_link_counts "$1")

    # <n> <singular> <plural> — the phrase is the whole detail, not a fragment
    # something else appends "link(s)" to.
    _phrase() { (( $1 == 1 )) && printf '%s' "$2" || printf '%s' "${3//<n>/$1}"; }

    local out=""
    (( n_missing )) && out="$(_phrase "$n_missing" "1 link not created yet" "<n> links not created yet")"
    (( n_broken ))  && out="${out:+$out, }$(_phrase "$n_broken" "1 dangling link" "<n> dangling links")"
    (( n_foreign )) && out="${out:+$out, }$(_phrase "$n_foreign" "1 path already in use" "<n> paths already in use")"
    unset -f _phrase
    printf '%s' "${out:-link problem}"
}

# ---- the repo itself -----------------------------------------------------
# health_drift — managed files that differ from what is committed, one
# `<git-status><TAB><repo-relative-path>` per line.
#
# Configs are symlinks into the repo, which is the feature: edit once, every
# machine follows. It is also the hazard — a tool that "helpfully" appends to
# ~/.zshrc is appending to a tracked file, and the next `envup upgrade` fails
# its git pull for reasons that have nothing to do with envup. (This is not
# hypothetical: nvm's installer did exactly that to this repo.) `envup adopt`
# is the way out; this function is how you find out you need it.
health_drift() {
    have git || return 0
    git -C "$ENVUP_HOME" rev-parse --git-dir >/dev/null 2>&1 || return 0
    local line st path
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        st="${line:0:2}"; path="${line:3}"
        # Submodules report as modified whenever their checked-out commit moves;
        # that is plugin state, not pollution, and it has its own lock files.
        [[ "$st" == " M" && -f "$ENVUP_HOME/$path/.git" ]] && continue
        [[ -d "$ENVUP_HOME/$path/.git" ]] && continue
        printf '%s\t%s\n' "$st" "$path"
    # Trailing '/*' matters: a git pathspec is matched against the full path and
    # its wildcards do not imply recursion, so bare 'modules/*/files' matches
    # the directory name and nothing inside it. (In the default pathspec syntax
    # '*' does cross '/', so this one form covers nested files too.)
    done < <(git -C "$ENVUP_HOME" status --porcelain -- 'modules/*/files/*' 2>/dev/null)
}
