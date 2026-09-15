#!/usr/bin/env bash
# envup lint — static checks over all first-party shell sources.
# Runs `bash -n` (syntax) + shellcheck. Shared by CI and local dev.
#
# Zsh sources (completions/_envup, modules/*/files/**/*.zsh) are intentionally
# excluded: shellcheck does not support zsh.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2

shopt -s nullglob
files=(envup lib.sh lib/*.sh modules/*/*.sh modules/*/files/bin/*
       profiles/*.sh scripts/*.sh tests/integration/*.sh)

rc=0

echo "==> bash -n (syntax check) on ${#files[@]} files"
for f in "${files[@]}"; do
    bash -n "$f" || { echo "  syntax error: $f" >&2; rc=1; }
done

echo "==> shellcheck"
if command -v shellcheck >/dev/null 2>&1; then
    # Module hooks do `source ./meta.sh` — relative, because run_module_hook
    # cd's into the module dir first. shellcheck only resolves that with
    # --source-path=SCRIPTDIR (0.7.0+). Older builds (e.g. the 0.6.0 in EL8)
    # would report SC1091 on every hook, so pass the flag only when supported.
    sc_opts=(-x)
    if shellcheck --source-path=SCRIPTDIR --version >/dev/null 2>&1; then
        sc_opts+=(--source-path=SCRIPTDIR)
    else
        echo "  note: shellcheck $(shellcheck --version | awk '/^version:/{print $2}') predates" \
             "--source-path; sourced-file resolution is off (upgrade to >= 0.7.0)." >&2
        sc_opts+=(-e SC1091)
    fi
    shellcheck "${sc_opts[@]}" "${files[@]}" || rc=1
else
    echo "  shellcheck not found on PATH — install it to run static analysis." >&2
    rc=1
fi

# Soft guard (non-fatal): each library file is one cohesive concern and is meant
# to stay readable in a sitting. Past the threshold it is probably two concerns —
# split it out as lib/<name>.sh and source it from lib.sh (see ARCHITECTURE).
#
# lib/providers/*.sh are in the list too. They were left out originally as
# "just one route each", and github_release quietly grew to within five lines
# of the threshold without anyone being told — a budget nobody measures is a
# budget nobody has.
echo "==> library file sizes"
lib_threshold=360
for f in lib.sh lib/*.sh lib/providers/*.sh; do
    n=$(wc -l < "$f")
    if (( n > lib_threshold )); then
        echo "  note: $f is ${n} lines (> ${lib_threshold}); consider splitting a section." >&2
    else
        printf '  %-28s %3d/%d lines\n' "$f" "$n" "$lib_threshold"
    fi
done

if [[ $rc -eq 0 ]]; then
    echo "lint: OK"
else
    echo "lint: FAILED" >&2
fi
exit $rc
