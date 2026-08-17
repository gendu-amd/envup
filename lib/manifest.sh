#!/bin/bash
# ============================================
# envup — the installed-module manifest
# ============================================
# Plain text under $ENVUP_STATE_DIR. Deliberately outside the repo: what is
# installed is a property of the machine, not of the dotfiles, and two machines
# sharing this repo over NFS must not overwrite each other's answer.
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

_manifest_ensure() {
    mkdir -p "$ENVUP_STATE_DIR"
    [[ -f "$ENVUP_MANIFEST" ]] && return 0
    printf '# envup-manifest schema=%s\n# repo_root=%s\n' \
        "$ENVUP_MANIFEST_SCHEMA" "${ENVUP_HOME:-}" >"$ENVUP_MANIFEST"
}

# _manifest_rows — the data lines: comments and blanks dropped.
_manifest_rows() {
    [[ -f "$ENVUP_MANIFEST" ]] || return 0
    grep -v -e '^[[:space:]]*#' -e '^[[:space:]]*$' "$ENVUP_MANIFEST" 2>/dev/null || true
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
    _manifest_ensure
    manifest_remove "$mod"
    printf '%s\t%s\t%s\t%s\t%s\n' "$mod" "$state" "$prov" "$ver" "$ts" >>"$ENVUP_MANIFEST"
}

# manifest_add <mod> [state] — the details-free form, for callers that only know
# that it is installed.
manifest_add() { manifest_record "$1" "${2:-ok}"; }

manifest_remove() {
    [[ -f "$ENVUP_MANIFEST" ]] || return 0
    # Field 1 only: a schema-2 row is `name<TAB>...`, and with -F'\t' a comment
    # line is one field that never equals a module name, so the header survives.
    awk -F'\t' -v m="$1" '$1 != m' "$ENVUP_MANIFEST" >"$ENVUP_MANIFEST.tmp" &&
        mv -f "$ENVUP_MANIFEST.tmp" "$ENVUP_MANIFEST"
}

# ---- repo_root -----------------------------------------------------------
manifest_root() {
    [[ -f "$ENVUP_MANIFEST" ]] || return 0
    sed -n 's/^#[[:space:]]*repo_root=//p' "$ENVUP_MANIFEST" | head -1
}

manifest_set_root() {
    _manifest_ensure
    if grep -q '^#[[:space:]]*repo_root=' "$ENVUP_MANIFEST"; then
        awk -v r="$1" '
            /^#[[:space:]]*repo_root=/ && !done { print "# repo_root=" r; done = 1; next }
            { print }
        ' "$ENVUP_MANIFEST" >"$ENVUP_MANIFEST.tmp" && mv -f "$ENVUP_MANIFEST.tmp" "$ENVUP_MANIFEST"
    else
        # An upgraded schema-1 file: give it the header it never had.
        { printf '# repo_root=%s\n' "$1"; cat "$ENVUP_MANIFEST"; } >"$ENVUP_MANIFEST.tmp" &&
            mv -f "$ENVUP_MANIFEST.tmp" "$ENVUP_MANIFEST"
    fi
}
