# ============================================
# 10 — PATH construction
# ============================================
# Every later slice, and every hosts/ file, adds to PATH through these two
# helpers instead of writing `export PATH=...` by hand. Two reasons:
#
#   - `export PATH=$PATH:/opt/rocm/bin` in a slice that runs in every shell
#     appends again in every nested shell. Inside tmux inside ssh, PATH grew
#     without bound; `typeset -U` plus these helpers make it idempotent.
#   - a directory that does not exist should not be on PATH at all. It costs a
#     stat on every command lookup and hides typos.
#
# LD_LIBRARY_PATH and friends are plain strings, not zsh arrays, so they get
# their own helper with the same contract.

typeset -gU path PATH

# path_prepend <dir>... — put these first (they win over what is installed).
path_prepend() {
    local d
    for d in "$@"; do
        [[ -d "$d" ]] || continue
        path=("$d" ${path:#$d})
    done
}

# path_append <dir>... — put these last (a fallback, not an override).
path_append() {
    local d
    for d in "$@"; do
        [[ -d "$d" ]] || continue
        path=(${path:#$d} "$d")
    done
}

# envvar_path_append <VAR> <dir>... — the same idempotence for colon-separated
# string variables such as LD_LIBRARY_PATH, MANPATH or PKG_CONFIG_PATH.
envvar_path_append() {
    local var="$1"; shift
    local -a parts
    local d cur
    cur="${(P)var}"
    parts=(${(s.:.)cur})
    for d in "$@"; do
        [[ -d "$d" ]] || continue
        parts=(${parts:#$d} "$d")
    done
    parts=(${parts:#})
    export "$var=${(j.:.)parts}"
}
