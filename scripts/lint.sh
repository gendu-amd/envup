#!/usr/bin/env bash
# envup lint — static checks over all first-party shell sources.
# Runs `bash -n` (syntax) + shellcheck. Shared by CI and local dev.
#
# Zsh sources (completions/_envup, modules/*/files/**/*.zsh) are intentionally
# excluded: shellcheck does not support zsh.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2

shopt -s nullglob
files=(envup lib.sh modules/*/*.sh profiles/*.sh scripts/*.sh tests/integration/*.sh)

rc=0

echo "==> bash -n (syntax check) on ${#files[@]} files"
for f in "${files[@]}"; do
    bash -n "$f" || { echo "  syntax error: $f" >&2; rc=1; }
done

echo "==> shellcheck"
if command -v shellcheck >/dev/null 2>&1; then
    shellcheck -x "${files[@]}" || rc=1
else
    echo "  shellcheck not found on PATH — install it to run static analysis." >&2
    rc=1
fi

# Soft guard (non-fatal): lib.sh is meant to stay small. Past the threshold,
# consider splitting a section into lib/<name>.sh (see ARCHITECTURE).
echo "==> lib.sh size"
lib_lines=$(wc -l < lib.sh)
lib_threshold=400
if (( lib_lines > lib_threshold )); then
    echo "  note: lib.sh is ${lib_lines} lines (> ${lib_threshold}); consider splitting a section." >&2
else
    echo "  lib.sh ${lib_lines}/${lib_threshold} lines"
fi

if [[ $rc -eq 0 ]]; then
    echo "lint: OK"
else
    echo "lint: FAILED" >&2
fi
exit $rc
