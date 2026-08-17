#!/bin/bash
# ============================================
# envup — is this tool actually here, and does it actually work?
# ============================================
# Split out of engine.sh, which was over the size budget, but the seam is real
# and not just arithmetic: nothing in here is about installing anything. It
# answers one question — "can this machine run <tool>, at a good enough
# version?" — and four different callers ask it:
#
#   engine.sh   before choosing a provider, and again after one claims success
#   health.sh   for `envup status`, on a machine nobody is installing to
#   doctor.sh   the same, plus the version comparison
#   hooks.sh    modules use bin_path / bin_version directly (see CONTRIBUTING)
#
# Because `status` and `doctor` are read-only commands, everything here must be
# free of side effects. That is a contract, not a coincidence: engine_verify is
# the function a module overrides in hooks.sh, and a verify() that installs
# something would make `envup status` mutate the machine.
#
# The recurring hazard is that "on PATH" and "works" are different facts. A
# prebuilt binary built against a newer glibc installs perfectly and then dies
# on every invocation; a tool can be present and three major versions too old.
# Both look identical to `command -v`.
#
# Depends on: log.sh
# ============================================

# Where user-space installs go. Everything root-free lands here, which is also
# why bin_path has to look here explicitly: the directory may not be on PATH in
# the process that just created it.
ENVUP_LOCAL_BIN="${ENVUP_LOCAL_BIN:-$HOME/.local/bin}"

# bin_path <name> — where this binary actually is, including the user-space dir
# that may not be on PATH yet in this process (we just created it).
bin_path() {
    local b="$1" p
    p="$(command -v "$b" 2>/dev/null)" && { printf '%s' "$p"; return 0; }
    [[ -x "$ENVUP_LOCAL_BIN/$b" ]] && { printf '%s' "$ENVUP_LOCAL_BIN/$b"; return 0; }
    return 1
}

# bin_runs <name> — does this binary actually execute on this machine? Being on
# PATH and +x is not the same thing: a prebuilt binary linked against a newer
# glibc than the host has gets installed happily and then dies on every call
# with "version `GLIBC_2.33' not found". Asking it for its version is the
# cheapest way to make it prove itself.
bin_runs() {
    local p; p="$(bin_path "$1")" || return 1
    # Unquoted on purpose: a module may need more than one word ("version -q").
    # shellcheck disable=SC2086
    "$p" ${VERIFY_VERSION_ARG:---version} >/dev/null 2>&1
}

# bin_version <name> — first dotted number the tool prints. Deliberately loose
# about the format (every tool differs and we only ever compare it), strict
# about two things:
#
#   - a non-zero exit means no answer. Scraping the failure message above gave
#     nvim a confident "2.33" and a green tick for a binary that cannot start.
#   - stdout first. stderr is read only after a clean exit, for the few tools
#     that print their banner there, so a warning can never become a version.
bin_version() {
    local p; p="$(bin_path "$1")" || return 1
    local v out
    # shellcheck disable=SC2086
    out="$("$p" ${VERIFY_VERSION_ARG:---version} 2>/dev/null)" || return 1
    v="$(printf '%s\n' "$out" | head -3 | grep -oE '[0-9]+(\.[0-9]+)+' | head -1)"
    # shellcheck disable=SC2086
    [[ -n "$v" ]] || v="$("$p" ${VERIFY_VERSION_ARG:---version} 2>&1 >/dev/null |
        head -3 | grep -oE '[0-9]+(\.[0-9]+)+' | head -1)"
    [[ -n "$v" ]] || return 1
    printf '%s' "$v"
}

# version_ge <have> <want> — true when <have> is at least <want>.
version_ge() {
    # A trailing zero component carries no information — 0.9 and 0.9.0 are the
    # same version — but sort -V orders the shorter string first, so without
    # this a tool reporting "0.9" reads as older than a floor of "0.9.0", the
    # chain declares it too old, and the provider reinstalls what is there.
    local a="$1" b="$2"
    while [[ "$a" == *.0 ]]; do a="${a%.0}"; done
    while [[ "$b" == *.0 ]]; do b="${b%.0}"; done
    [[ "$a" == "$b" ]] && return 0
    [[ "$(printf '%s\n%s\n' "$a" "$b" | sort -V | head -1)" == "$b" ]]
}

# engine_verify — is the tool present and good enough? A module may replace this
# wholesale by defining verify() in hooks.sh.
engine_verify() {
    declare -F verify >/dev/null && { verify; return $?; }
    [[ -n "$VERIFY_BIN" ]] || return 0
    bin_path "$VERIFY_BIN" >/dev/null || return 1
    # Present is not the same as working. A module whose tool has no --version
    # (or answers on a flag envup cannot guess) sets VERIFY_VERSION_ARG, or
    # replaces this check wholesale with verify() in hooks.sh.
    bin_runs "$VERIFY_BIN" || return 1
    [[ -n "$VERIFY_MIN_VERSION" ]] || return 0
    local v; v="$(bin_version "$VERIFY_BIN")" || return 1
    version_ge "$v" "$VERIFY_MIN_VERSION"
}
