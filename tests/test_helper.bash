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
    # lib.sh resolves lib/ relative to its own path, and BASH_SOURCE follows the
    # symlink's *name*, not its target — so the sandbox needs lib/ beside it.
    ln -sf "$REPO_ROOT/lib.sh" "$ENVUP_HOME/lib.sh"
    ln -sf "$REPO_ROOT/lib"    "$ENVUP_HOME/lib"
    export ENVUP_STATE_DIR="$TEST_TMP/state"
    export ENVUP_BACKUP_DIR="$TEST_TMP/backup"
    unset ENVUP_DRY_RUN

    # A directory at the front of PATH where a test can drop fake tools.
    ORIG_PATH="$PATH"
    export STUB_BIN="$TEST_TMP/stub-bin"; mkdir -p "$STUB_BIN"
    export PATH="$STUB_BIN:$PATH"

    # Pin the capabilities that cost a fork or a network round trip. Tests must
    # not depend on whether the machine running them happens to have passwordless
    # sudo or a reachable github.com; the ones that care about detection unset
    # these and probe for real.
    export ENVUP_PRIV="${ENVUP_PRIV:-none}"
    export ENVUP_NET="${ENVUP_NET:-offline}"

    # shellcheck source=/dev/null
    source "$REPO_ROOT/lib.sh"
}

common_teardown() {
    # Put PATH back first: isolate_path points it inside TEST_TMP, so tearing the
    # sandbox down while PATH still lives in it leaves the shell unable to find
    # `rm` halfway through its own cleanup.
    [[ -n "${ORIG_PATH:-}" ]] && export PATH="$ORIG_PATH"
    [[ -n "${TEST_TMP:-}" && -d "$TEST_TMP" ]] && rm -rf "$TEST_TMP"
    return 0
}

# ---- fake environments ---------------------------------------------------
# The capability layer answers questions about the machine — does sudo want a
# password, is github reachable, did `apt-get update` fail. Those answers cannot
# be tested on the machine running the tests: it has one fixed set of them, and
# it is never the interesting set. So we fake the tools instead.

# stub_bin NAME  (script on stdin) — install a fake executable at the front of
# PATH. Use it to make a tool behave the way a hostile machine would.
stub_bin() {
    local name="$1" f="$STUB_BIN/$1"
    cat > "$f"
    chmod +x "$f"
    [[ -s "$f" ]] || { echo "stub_bin $name: empty script" >&2; return 1; }
}

# isolate_path [extra tool...] — rebuild PATH so it holds only the stub dir plus
# a known-good minimum. The point is what's *missing*: sudo is not in the
# default set, which is the only way to test "this server has no sudo at all"
# from a machine that has one.
isolate_path() {
    local d="$TEST_TMP/isolated-bin" t p
    rm -rf "$d"; mkdir -p "$d"
    for t in bash sh env id uname grep sed awk head tail cat date hostname \
             stat df getconf ldd readlink dirname basename ls mkdir rmdir rm \
             ln mv cp chmod touch tee sort tr cut wc timeout gtimeout \
             python3 git curl wget "$@"; do
        p="$(command -v "$t" 2>/dev/null)" || continue
        [[ -x "$p" ]] && ln -sf "$p" "$d/$t"
    done
    export PATH="$STUB_BIN:$d"
}

# lib_in_env VAR=VAL... -- <shell code> — source lib.sh in a fresh bash with the
# given environment, and run <shell code> against it. Capability detection is
# cached in exported variables, so exercising a *different* verdict means
# starting a process that has not cached one yet.
lib_in_env() {
    local -a envs=()
    while (($#)) && [[ "$1" != -- ]]; do envs+=("$1"); shift; done
    shift   # the --
    # -u BASH_ENV: a non-interactive bash sources $BASH_ENV, and on a machine
    # with an HPC module system or similar that file writes to stderr. It would
    # land in the captured output and break assertions for reasons that have
    # nothing to do with envup.
    env -u BASH_ENV -u ENV "${envs[@]}" bash -c "source '$REPO_ROOT/lib.sh'; $*" </dev/null
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
