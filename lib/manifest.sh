#!/bin/bash
# ============================================
# envup — the installed-module manifest
# ============================================
# Plain text under $ENVUP_STATE_DIR. Deliberately outside the repo: what is
# installed is a property of the machine, not of the dotfiles. On a shared HOME,
# log.sh scopes that directory by hostname so two machines do not overwrite each
# other's answer.
#
# Format (schema 2) — a comment header followed by one tab-separated row per
# module:
#
#     # envup-manifest schema=2
#     # repo_root=/home/me/envup
#     zoxide<TAB>ok<TAB>github_release<TAB>0.10.0<TAB>2026-08-15T09:12:03Z
#
# Schema 1 was the module name alone. Field 1 is still the name, so every reader
# here works unchanged on an old file; the extra columns just come back empty.
# That is the whole migration.
#
# The columns exist to answer questions the name cannot:
#   state     what the install actually achieved (ok / degraded)
#   provider  which route worked here — the useful thing to know when the same
#             module behaves differently on two machines
#   version   what was installed, so `doctor` can notice a downgrade
#   time      when, for reading logs after the fact
# repo_root records where the repo was when the links were made: moving the
# checkout dangles every symlink, and this is how `doctor` recognises that
# rather than reporting twenty unrelated breakages.
#
# Depends on: log.sh
# ============================================

ENVUP_MANIFEST="$ENVUP_STATE_DIR/installed"   # $ENVUP_STATE_DIR: see lib/log.sh
ENVUP_MANIFEST_SCHEMA=2

_manifest_read_file() {
    if [[ -f "$ENVUP_MANIFEST" ]]; then
        printf '%s' "$ENVUP_MANIFEST"
    elif [[ -n "${ENVUP_LEGACY_STATE_DIR:-}" && -f "$ENVUP_LEGACY_STATE_DIR/installed" ]]; then
        # Read-only commands must see the pre-host-scoping manifest without
        # creating or migrating anything. The first mutating command copies it.
        printf '%s' "$ENVUP_LEGACY_STATE_DIR/installed"
    fi
}

_manifest_ensure_unlocked() {
    mkdir -p "$ENVUP_STATE_DIR"
    [[ -f "$ENVUP_MANIFEST" ]] && return 0
    local tmp
    tmp="$(mktemp "${ENVUP_MANIFEST}.tmp.XXXXXX")" || return 1
    if printf '# envup-manifest schema=%s\n# repo_root=%s\n' \
        "$ENVUP_MANIFEST_SCHEMA" "${ENVUP_HOME:-}" >"$tmp"; then
        mv -f "$tmp" "$ENVUP_MANIFEST"
    else
        rm -f "$tmp"
        return 1
    fi
}

_manifest_lock_acquire() {
    local lock="$ENVUP_MANIFEST.lock" tries=0 pid=""
    mkdir -p "$ENVUP_STATE_DIR" || return 1
    while ! mkdir "$lock" 2>/dev/null; do
        if [[ -r "$lock/pid" ]]; then
            read -r pid <"$lock/pid" || pid=""
            if [[ "$pid" =~ ^[0-9]+$ ]] && ! kill -0 "$pid" 2>/dev/null; then
                rm -f "$lock/pid"
                rmdir "$lock" 2>/dev/null || true
                continue
            fi
        fi
        (( ++tries >= 100 )) && {
            log_error "manifest is busy: $ENVUP_MANIFEST"
            return 1
        }
        sleep 0.1
    done
    printf '%s\n' "${BASHPID:-$$}" >"$lock/pid"
}

_manifest_with_lock() (
    _envup_state_migrate || exit 1
    _manifest_lock_acquire || exit 1
    local lock="$ENVUP_MANIFEST.lock"
    trap 'rm -f "$lock/pid"; rmdir "$lock" 2>/dev/null || true' EXIT
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM
    "$@"
)

_manifest_ensure() {
    _manifest_with_lock _manifest_ensure_unlocked
}

# _manifest_rows — the data lines: comments and blanks dropped.
_manifest_rows() {
    local src; src="$(_manifest_read_file)"
    [[ -n "$src" ]] || return 0
    grep -v -e '^[[:space:]]*#' -e '^[[:space:]]*$' "$src" 2>/dev/null || true
}

manifest_list() { _manifest_rows | cut -f1; }
manifest_has()  { manifest_list | grep -qxF "$1"; }

# manifest_get <mod> <state|provider|version|time>
manifest_get() {
    local col
    case "$2" in
        state) col=2 ;; provider) col=3 ;; version) col=4 ;; time) col=5 ;;
        *) return 1 ;;
    esac
    _manifest_rows | awk -F'\t' -v m="$1" -v c="$col" '$1 == m { print $c; exit }'
}

# manifest_record <mod> [state] [provider] [version] — upsert one row.
manifest_record() {
    local mod="$1" state="${2:-ok}" prov="${3:-}" ver="${4:-}" ts
    ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" || ts=""
    _manifest_with_lock _manifest_record_unlocked "$mod" "$state" "$prov" "$ver" "$ts"
}

_manifest_record_unlocked() {
    local mod="$1" state="$2" prov="$3" ver="$4" ts="$5" tmp
    _manifest_ensure_unlocked || return 1
    tmp="$(mktemp "${ENVUP_MANIFEST}.tmp.XXXXXX")" || return 1
    if awk -F'\t' -v m="$mod" '$1 != m' "$ENVUP_MANIFEST" >"$tmp" &&
       printf '%s\t%s\t%s\t%s\t%s\n' "$mod" "$state" "$prov" "$ver" "$ts" >>"$tmp"; then
        mv -f "$tmp" "$ENVUP_MANIFEST"
    else
        rm -f "$tmp"
        return 1
    fi
}

# manifest_add <mod> [state] — the details-free form, for callers that only know
# that it is installed.
manifest_add() { manifest_record "$1" "${2:-ok}"; }

manifest_remove() {
    _manifest_with_lock _manifest_remove_unlocked "$1"
}

_manifest_remove_unlocked() {
    local mod="$1" tmp
    [[ -f "$ENVUP_MANIFEST" ]] || return 0
    # Field 1 only: a schema-2 row is `name<TAB>...`, and with -F'\t' a comment
    # line is one field that never equals a module name, so the header survives.
    tmp="$(mktemp "${ENVUP_MANIFEST}.tmp.XXXXXX")" || return 1
    if awk -F'\t' -v m="$mod" '$1 != m' "$ENVUP_MANIFEST" >"$tmp"; then
        mv -f "$tmp" "$ENVUP_MANIFEST"
    else
        rm -f "$tmp"
        return 1
    fi
}

# ---- repo_root -----------------------------------------------------------
manifest_root() {
    local src; src="$(_manifest_read_file)"
    [[ -n "$src" ]] || return 0
    sed -n 's/^#[[:space:]]*repo_root=//p' "$src" | head -1
}

manifest_set_root() {
    _manifest_with_lock _manifest_set_root_unlocked "$1"
}

_manifest_set_root_unlocked() {
    local root="$1" tmp
    _manifest_ensure_unlocked || return 1
    tmp="$(mktemp "${ENVUP_MANIFEST}.tmp.XXXXXX")" || return 1
    if grep -q '^#[[:space:]]*repo_root=' "$ENVUP_MANIFEST"; then
        if awk -v r="$root" '
            /^#[[:space:]]*repo_root=/ && !done { print "# repo_root=" r; done = 1; next }
            { print }
        ' "$ENVUP_MANIFEST" >"$tmp"; then
            mv -f "$tmp" "$ENVUP_MANIFEST"
        else
            rm -f "$tmp"
            return 1
        fi
    else
        # An upgraded schema-1 file: give it the header it never had.
        if { printf '# repo_root=%s\n' "$root"; cat "$ENVUP_MANIFEST"; } >"$tmp"; then
            mv -f "$tmp" "$ENVUP_MANIFEST"
        else
            rm -f "$tmp"
            return 1
        fi
    fi
}
