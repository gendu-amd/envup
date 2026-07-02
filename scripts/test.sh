#!/usr/bin/env bash
# envup test runner — bats unit + integration(dry-run) suites.
# Usage: scripts/test.sh [bats-args...]   (default: run tests/unit + tests/integration)
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2

if ! command -v bats >/dev/null 2>&1; then
    echo "bats not found on PATH — install bats-core to run the test suite." >&2
    exit 1
fi

suites=()
[[ -d tests/unit ]] && suites+=(tests/unit)
[[ -d tests/integration ]] && suites+=(tests/integration)

if [[ $# -gt 0 ]]; then
    exec bats "$@"
fi
exec bats --recursive "${suites[@]}"
