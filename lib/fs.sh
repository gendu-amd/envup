#!/bin/bash
# ============================================
# envup — paths, symlinks, managed text blocks
# ============================================
# The three invariants envup is built on all live here:
#   I1 backup-never-clobber  a real file at a link target is moved aside first
#   I2 idempotent            re-running changes nothing that is already right
#   I3 reversible            uninstall removes envup's own symlinks and nothing else
#
# All three depend on being able to answer "are these two names the same file?"
# on a machine whose readlink may not have -f and whose $HOME may be reachable
# by more than one path. That is what _realpath and paths_same are for, and why
# they are the first thing in this file.
#
# Depends on: log.sh
# ============================================

# ---- path resolution -----------------------------------------------------
# _realpath <path> — absolute, symlink-resolved path. Prints the best answer it
# can even for a path that doesn't exist yet.
#
# Three tiers, because no single implementation is portable:
#   readlink -f  GNU coreutils. Absent on macOS, whose BSD readlink has no -f
#                (and whose `realpath` only arrived in Ventura).
#   python3      almost always present, and os.path.realpath is exactly right.
#   pure shell   a stripped container may have neither of the above.
# The chosen tier is cached in the environment: this runs on every link
# comparison, and each hook subshell would otherwise re-probe.
_realpath() {
    local p="${1:-}"
    [[ -z "$p" ]] && return 1
    [[ "$p" != /* ]] && p="$PWD/$p"

    if [[ -z "${_ENVUP_REALPATH_IMPL:-}" ]]; then
        # BSD readlink -f on a directory prints nothing and exits 1, so this
        # probe cleanly separates GNU from BSD instead of guessing by OS.
        if readlink -f / >/dev/null 2>&1;   then _ENVUP_REALPATH_IMPL=readlink
        elif have python3;                  then _ENVUP_REALPATH_IMPL=python3
        else                                     _ENVUP_REALPATH_IMPL=shell
        fi
        export _ENVUP_REALPATH_IMPL
    fi

    case "$_ENVUP_REALPATH_IMPL" in
        readlink) readlink -f "$p" 2>/dev/null && return 0 ;;
        python3)  python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$p" 2>/dev/null && return 0 ;;
    esac
    _realpath_shell "$p"   # also the fallback when the preferred tier fails
}

_realpath_shell() {
    local p="$1" target dir base hops=0
    # Follow the final component while it is a symlink. Bounded, because a
    # symlink loop is a thing that exists and must not become a hang.
    while [[ -L "$p" ]]; do
        (( ++hops > 40 )) && break
        target="$(readlink "$p" 2>/dev/null)" || break
        [[ -z "$target" ]] && break
        case "$target" in
            /*) p="$target" ;;
            *)  p="${p%/*}/$target" ;;
        esac
    done

    while [[ "$p" == */ && "$p" != / ]]; do p="${p%/}"; done
    [[ "$p" == / ]] && { printf '/\n'; return 0; }

    base="${p##*/}"; dir="${p%/*}"; [[ -z "$dir" ]] && dir=/
    # cd -P resolves every symlink in the directory part. Inside a substitution,
    # so the caller's cwd is untouched. If the directory doesn't exist we keep
    # it as written — an unresolvable path still needs to compare consistently.
    dir="$(cd -P "$dir" 2>/dev/null && pwd -P)" || dir="${p%/*}"
    [[ -z "$dir" ]] && dir=/
    [[ "$dir" == / ]] && { printf '/%s\n' "$base"; return 0; }
    printf '%s/%s\n' "$dir" "$base"
}

# paths_same <a> <b> — true when both names denote the same file. Used to decide
# "is this link already correct?", so a false negative is not harmless: it makes
# every install tear down and recreate links that were already fine.
paths_same() {
    local a="$1" b="$2"
    [[ "$a" == "$b" ]] && return 0
    local ra rb
    ra="$(_realpath "$a")"; rb="$(_realpath "$b")"
    [[ -n "$ra" && "$ra" == "$rb" ]]
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
    # Already pointing where we want it. Compare the raw target first (cheap,
    # and exact for the links we create ourselves) before paying for resolution.
    if [[ -L "$dst" ]] && { [[ "$(readlink "$dst" 2>/dev/null)" == "$src" ]] || paths_same "$dst" "$src"; }; then
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

# ---- ownership -----------------------------------------------------------
# is_envup_link <path> — true when <path> is a symlink pointing into the repo.
# This is the guard on every deletion, so it has to be both strict (never claim
# a user's own file) and forgiving of the ways one directory acquires two names.
#
# Both the raw target and the resolved one are checked, against both the raw and
# the resolved $ENVUP_HOME, because either side can be the odd one out:
#   - On an autofs/NFS home, the repo as the user typed it (/home/me/envup) and
#     the link target as the kernel reports it (/mnt/home/me/envup) are the same
#     directory under two names. Comparing only resolved-to-raw fails, and
#     `uninstall` then walks away leaving every symlink it created behind.
#   - On a macOS without coreutils the old code fell back to a BSD readlink that
#     doesn't resolve at all, so the comparison could never match.
is_envup_link() {
    [[ -L "$1" ]] || return 1
    [[ -n "${ENVUP_HOME:-}" ]] || return 1

    local home_raw="${ENVUP_HOME%/}" home_res target
    home_res="$(_realpath "$ENVUP_HOME")"
    # A repo at / would make the prefix test match everything. It can't happen,
    # but the cost of refusing is one line and the cost of being wrong is rm -f.
    [[ "$home_raw" == / || "$home_res" == / ]] && return 1

    for target in "$(readlink "$1" 2>/dev/null)" "$(_realpath "$1")"; do
        [[ -z "$target" ]] && continue
        [[ "$target" == "$home_raw"/* || "$target" == "$home_res"/* ]] && return 0
    done
    return 1
}

unlink_safe() {
    local dst="$1"
    is_envup_link "$dst" || { log_info "skip (not an envup link): $dst"; return 0; }
    if [[ "${ENVUP_DRY_RUN:-0}" == 1 ]]; then log_info "[dry-run] rm $dst"; return 0; fi
    rm -f "$dst" && log_success "unlinked: $dst"
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
