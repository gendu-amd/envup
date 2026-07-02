# shellcheck shell=bash
# Shared setup for envup bats tests.
#
# Each test runs in a throwaway sandbox: a temp $HOME, a temp $ENVUP_HOME repo,
# and temp state/backup dirs — so tests never touch the real machine and never
# depend on each other. lib.sh is sourced against that sandbox.

# Resolve the real repo root from the test file location (tests/<x>/*.bats).
_envup_repo_root() { cd "$BATS_TEST_DIRNAME/../.." && pwd; }

common_setup() {
    REPO_ROOT="$(_envup_repo_root)"
    TEST_TMP="$(mktemp -d "${BATS_TMPDIR:-/tmp}/envup.XXXXXX")"

    export HOME="$TEST_TMP/home";       mkdir -p "$HOME"
    export ENVUP_HOME="$TEST_TMP/repo"; mkdir -p "$ENVUP_HOME/modules"
    # run_module_hook's watchdog child re-sources $ENVUP_HOME/lib.sh; make the
    # sandbox repo provide it (production ENVUP_HOME always contains lib.sh).
    ln -sf "$REPO_ROOT/lib.sh" "$ENVUP_HOME/lib.sh"
    export ENVUP_STATE_DIR="$TEST_TMP/state"
    export ENVUP_BACKUP_DIR="$TEST_TMP/backup"
    unset ENVUP_DRY_RUN

    # shellcheck source=/dev/null
    source "$REPO_ROOT/lib.sh"
}

common_teardown() {
    [[ -n "${TEST_TMP:-}" && -d "$TEST_TMP" ]] && rm -rf "$TEST_TMP"
    return 0
}

# mk_module NAME [dep...] — create a fixture module with a meta.sh declaring DEPENDS.
mk_module() {
    local n="$1"; shift
    mkdir -p "$ENVUP_HOME/modules/$n"
    {
        echo '#!/bin/bash'
        echo "NAME=\"$n\""
        echo "DEPENDS=($*)"
    } > "$ENVUP_HOME/modules/$n/meta.sh"
}
