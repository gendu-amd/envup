#!/usr/bin/env bats
# System package managers (lib/pkg.sh).
#
# The interesting cases are all machines the test runner isn't: one whose
# apt-get cannot reach its mirror (the classic corporate-proxy failure), and one
# where the only manager needs a root we don't have. Both are faked with PATH
# stubs, because the point of this layer is to answer "can I even run this?"
# correctly, and the honest answer on a laptop is always yes.

load '../test_helper'

setup() { common_setup; }
teardown() { common_teardown; }

# An apt whose update fails the way a proxy-stripped one does, and whose install
# happens to succeed. Nothing here touches the real system.
_stub_apt() {
    stub_bin apt-get <<EOF
#!/bin/sh
case "\$1" in
  update)  echo "E: Could not resolve host: archive.ubuntu.com" >&2; exit $1 ;;
  install) shift; echo "apt-get install \$*"; exit 0 ;;
esac
exit 0
EOF
    isolate_path
}

# ---- refresh failure must not be cached as success (A7) ------------------

@test "pkg_install: a failed 'apt-get update' is reported and retried, not marked fresh (A7)" {
    # The old code set _pkg_updated=1 unconditionally. The next install then ran
    # against a stale/empty index and failed with "package not found" — which
    # sends you hunting for a missing package when the mirror was unreachable.
    _stub_apt 100
    run lib_in_env -u ENVUP_PRIV -u _pkg_updated ENVUP_PRIV=root \
        -- 'pkg_install foo; pkg_install bar'

    [ "$(grep -c 'refreshing package lists' <<<"$output")" -eq 2 ]
    [[ "$output" == *"package list refresh failed (rc=100)"* ]]
    # And it still tried the install rather than giving up on a warning.
    [[ "$output" == *"apt-get install -y foo"* ]]
    [[ "$output" == *"apt-get install -y bar"* ]]
}

@test "pkg_install: a successful refresh happens once, not per package" {
    _stub_apt 0
    run lib_in_env -u ENVUP_PRIV -u _pkg_updated ENVUP_PRIV=root \
        -- 'pkg_install foo; pkg_install bar'

    [ "$(grep -c 'refreshing package lists' <<<"$output")" -eq 1 ]
    [[ "$output" != *"refresh failed"* ]]
}

@test "pkg_install: the package manager's exit status survives the tee" {
    # `cmd | tee` reports tee's status. Getting this wrong makes every failed
    # install look successful unless the caller happened to set pipefail.
    stub_bin apt-get <<'EOF'
#!/bin/sh
case "$1" in update) exit 0 ;; esac
echo "E: Unable to locate package" >&2
exit 100
EOF
    isolate_path
    run lib_in_env -u ENVUP_PRIV -u _pkg_updated ENVUP_PRIV=root -- 'pkg_install nosuchpkg'
    [ "$status" -eq 100 ]
}

# ---- knowing when not to try (no root) -----------------------------------

@test "pkg_install: with no route to root it refuses instead of failing inside dpkg" {
    [ "$EUID" -ne 0 ] || skip "running as root; there is always a route"
    _stub_apt 0    # isolate_path leaves no sudo behind
    run lib_in_env -u ENVUP_PRIV -u _pkg_updated -- 'pkg_install foo'

    [ "$status" -eq 77 ]                          # ENVUP_RC_NOPRIV
    [[ "$output" == *"no route to it"* ]]
    [[ "$output" == *"install manually: foo"* ]]  # ...and what to do about it
    [[ "$output" != *"apt-get install"* ]]        # never actually invoked
}

@test "pkg_install: a dry run still succeeds on a machine that could not install" {
    # A preview that fails is not a preview — but it should say what it found.
    [ "$EUID" -ne 0 ] || skip "running as root; there is always a route"
    _stub_apt 0
    run lib_in_env -u ENVUP_PRIV -u _pkg_updated ENVUP_DRY_RUN=1 -- 'pkg_install foo'

    [ "$status" -eq 0 ]
    [[ "$output" == *"[dry-run]"* ]]
    [[ "$output" == *"no route to it"* ]]
    [[ "$output" != *"refreshing package lists"* ]]
}

@test "pkg_can_install: no supported manager at all is a clear no" {
    isolate_path        # no apt/dnf/yum/pacman/brew/apk
    run lib_in_env -u ENVUP_PRIV ENVUP_PRIV=root -- 'pkg_can_install; echo "rc=$?"; pkg_why_not'
    [[ "$output" == *"rc=1"* ]]
    [[ "$output" == *"no supported package manager"* ]]
}

# ---- user-space beats unreachable (no-root servers) ----------------------

@test "pkg: user-space brew is preferred over an apt we cannot run" {
    [ "$EUID" -ne 0 ] || skip "running as root; apt is usable"
    _stub_apt 0
    stub_bin brew <<'EOF'
#!/bin/sh
exit 0
EOF
    run lib_in_env -u ENVUP_PRIV -- 'printf "%s|" "$ENVUP_PKG"; pkg_can_install && printf usable'
    [[ "$output" == *"brew|usable"* ]]
}

@test "pkg: with root, the system manager stays the system manager" {
    _stub_apt 0
    stub_bin brew <<'EOF'
#!/bin/sh
exit 0
EOF
    run lib_in_env -u ENVUP_PRIV ENVUP_PRIV=root -- 'printf %s "$ENVUP_PKG"'
    [ "$output" = apt ]
}

@test "pkg_family: names the packaging tradition, not the distro" {
    # fd is "fd-find" on every Debian derivative, whatever /etc/os-release says.
    _stub_apt 0
    run lib_in_env -u ENVUP_PRIV ENVUP_PRIV=root -- 'pkg_family'
    [ "$output" = debian ]
}
