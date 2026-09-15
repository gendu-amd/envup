#!/bin/bash
# Portable path identity, backup-before-link, safe unlink, and managed blocks.

# ---- path resolution -----------------------------------------------------
# _realpath <path> — cached readlink -f, Python, then pure-shell fallback.
_realpath() {
    local p="${1:-}"
    [[ -z "$p" ]] && return 1
    [[ "$p" != /* ]] && p="$PWD/$p"

    if [[ -z "${_ENVUP_REALPATH_IMPL:-}" ]]; then
        # Probe behavior rather than guessing GNU/BSD from the OS.
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
    # Bound symlink traversal so a loop cannot hang the command.
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
    # Resolve the directory without changing the caller's cwd.
    dir="$(cd -P "$dir" 2>/dev/null && pwd -P)" || dir="${p%/*}"
    [[ -z "$dir" ]] && dir=/
    [[ "$dir" == / ]] && { printf '/%s\n' "$base"; return 0; }
    printf '%s/%s\n' "$dir" "$base"
}

# paths_same <a> <b> — true when both names resolve to the same path.
paths_same() {
    local a="$1" b="$2"
    [[ "$a" == "$b" ]] && return 0
    local ra rb
    ra="$(_realpath "$a")"; rb="$(_realpath "$b")"
    [[ -n "$ra" && "$ra" == "$rb" ]]
}

# ---- safe symlink (always backs up a pre-existing path) ------------------
ENVUP_BACKUP_DIR="${ENVUP_BACKUP_DIR:-$HOME/.dotfiles_backup/$(date +%Y%m%d_%H%M%S)}"

# Preserve the original path inside the backup to avoid basename collisions.
backup_path() {
    local dst="$1" rel
    # Keep non-HOME paths under root/ to avoid collisions.
    if [[ "$dst" == "$HOME/"* ]]; then rel="${dst#"$HOME"/}"; else rel="root${dst}"; fi
    printf '%s/%s' "$ENVUP_BACKUP_DIR" "$rel"
}

safe_link()          { _link "$1" "$2" required; }
safe_link_optional() { _link "$1" "$2" optional; }
_link() {
    local src="$1" dst="$2" mode="${3:-required}"
    [[ "$src" != /* ]] && src="$ENVUP_HOME/$src"
    if [[ ! -e "$src" ]]; then
        [[ "$mode" == optional ]] && { log_info "skip optional (not present): $src"; return 0; }
        log_error "source not found: $src"; log_hint "did you 'git clone --recursive'?"; return 1
    fi
    # Compare the raw target before resolving paths.
    if [[ -L "$dst" ]] && { [[ "$(readlink "$dst" 2>/dev/null)" == "$src" ]] || paths_same "$dst" "$src"; }; then
        log_info "already linked: $dst"; return 0
    fi
    if [[ "${ENVUP_DRY_RUN:-0}" == 1 ]]; then log_info "[dry-run] link $dst -> $src"; return 0; fi
    # Preserve every pre-existing destination, including dangling symlinks.
    if [[ -e "$dst" || -L "$dst" ]]; then
        local bak; bak="$(backup_path "$dst")"
        mkdir -p "${bak%/*}"
        mv "$dst" "$bak" || { log_error "backup failed: $dst"; return 1; }
        log_info "backup: $dst -> $bak"
    fi
    mkdir -p "$(dirname "$dst")"
    ln -sf "$src" "$dst" && log_success "linked: $dst"
}

# ---- ownership -----------------------------------------------------------
# Check raw and resolved targets so automounted HOME aliases remain owned.
is_envup_link() {
    [[ -L "$1" ]] || return 1
    [[ -n "${ENVUP_HOME:-}" ]] || return 1

    local home_raw="${ENVUP_HOME%/}" home_res target
    home_res="$(_realpath "$ENVUP_HOME")"
    # Never let the ownership prefix collapse to filesystem root.
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
    rm -f "$dst" || return 1
    log_success "unlinked: $dst"
    dir_prune_empty "${dst%/*}"
}

# Remove empty parents up to HOME; rmdir protects non-empty directories.
dir_prune_empty() {
    local dir="${1:-}" home="${HOME%/}" guard=0
    [[ -n "$dir" && -n "$home" ]] || return 0
    if [[ "${ENVUP_DRY_RUN:-0}" == 1 ]]; then
        [[ -d "$dir" && "$dir" == "$home"/* ]] && log_info "[dry-run] rmdir (if empty) $dir"
        return 0
    fi
    while [[ -d "$dir" && "$dir" == "$home"/* ]]; do
        (( ++guard > 32 )) && break            # a path this deep is a bug, not a home
        rmdir "$dir" 2>/dev/null || return 0   # not empty: done, and not an error
        log_info "removed empty directory: $dir"
        dir="${dir%/*}"
    done
    return 0
}

# Track files created solely to hold a managed block.
_created_ledger() { printf '%s/created' "$ENVUP_STATE_DIR"; }

created_note() {
    local f="$1" ledger; ledger="$(_created_ledger)"
    [[ "${ENVUP_DRY_RUN:-0}" == 1 ]] && return 0
    grep -qxF "$f" "$ledger" 2>/dev/null && return 0
    mkdir -p "${ledger%/*}" && printf '%s\n' "$f" >>"$ledger"
}

# Delete an empty file only when the creation ledger says envup made it.
created_reclaim() {
    local f="$1" ledger; ledger="$(_created_ledger)"
    [[ -f "$ledger" ]] || return 0
    grep -qxF "$f" "$ledger" 2>/dev/null || return 0
    if [[ "${ENVUP_DRY_RUN:-0}" == 1 ]]; then
        [[ -f "$f" && ! -s "$f" ]] && log_info "[dry-run] rm (empty, created by envup) $f"
        return 0
    fi
    # A symlinked rc file was never ours to delete.
    if [[ ! -L "$f" && -f "$f" && ! -s "$f" ]]; then
        rm -f "$f" && log_success "removed the empty $f envup created"
    fi
    { grep -vxF "$f" "$ledger" || true; } >"$ledger.tmp" && mv -f "$ledger.tmp" "$ledger"
    [[ -s "$ledger" ]] || rm -f "$ledger"
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
    mkdir -p "$(dirname "$file")"
    # Record creation before writing so block_del can safely reclaim it.
    [[ -e "$file" ]] || { touch "$file" && created_note "$file"; }
    block_del "$file" "$tag"
    printf '%s\n%s\n%s\n' "$_BLK_BEGIN" "$content" "$_BLK_END" >>"$file"
}
block_del() {
    local file="$1" tag="$2"; [[ -f "$file" ]] || return 0
    _block_markers "$tag"
    if [[ "${ENVUP_DRY_RUN:-0}" == 1 ]]; then log_info "[dry-run] remove '$tag' block from $file"; return 0; fi
    grep -qF "$_BLK_BEGIN" "$file" || return 0
    sed -i.envup-bak "\|^${_BLK_BEGIN}\$|,\|^${_BLK_END}\$|d" "$file" && rm -f "$file.envup-bak"
    created_reclaim "$file"
}
