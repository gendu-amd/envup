#!/usr/bin/env bats
# The capability layer (lib/caps.sh) — what this machine can actually do.
#
# Every assertion here is about a machine the test runner is NOT: a server whose
# sudo wants a password, an arm64 Mac, a host behind a proxy, a box with no way
# out to github. They are faked with PATH stubs (see test_helper's stub_bin /
# isolate_path), because these are exactly the situations that used to break
# envup in the field and could never be reproduced on a developer laptop.

load '../test_helper'

setup() { common_setup; }
teardown() { common_teardown; }

# ---- architecture --------------------------------------------------------

@test "caps: uname -m spellings collapse to one vocabulary" {
    # arm64 -> aarch64 is the one that matters: macOS says arm64 and essentially
    # no release asset is ever named that.
    local pair raw want
    for pair in arm64:aarch64 aarch64:aarch64 amd64:x86_64 x86_64:x86_64 \
                armv7l:armv7 i686:i686 ppc64le:ppc64le sparc64:sparc64; do
        raw="${pair%%:*}"; want="${pair##*:}"
        run lib_in_env -u ENVUP_ARCH "ENVUP_ARCH_RAW=$raw" -- 'printf %s "$ENVUP_ARCH"'
        [ "$output" = "$want" ]
    done
}

@test "caps: an inherited un-normalised ENVUP_ARCH is normalised anyway" {
    # 20-platform.zsh exports ENVUP_ARCH into every interactive shell, so an
    # envup run started from an installed shell inherits whatever it set.
    # Trusting it would put `arm64` back into asset matching on macOS.
    run lib_in_env ENVUP_ARCH=arm64 -- 'printf %s "$ENVUP_ARCH"'
    [ "$output" = aarch64 ]
    run lib_in_env ENVUP_ARCH=arm64 -- 'printf %s "$ENVUP_ARCH_RAW"'
    [ "$output" = "$(uname -m)" ]
}

# ---- privilege (A1) ------------------------------------------------------

@test "caps: sudo that demands a password is not usable, and saying so is instant (A1)" {
    [ "$EUID" -ne 0 ] || skip "running as root; there is no sudo path to test"
    # A locked-down server. -n refuses at once; any other invocation would sit at
    # a password prompt until something kills it — which is precisely what used
    # to happen, invisibly, for the full 900s module watchdog.
    stub_bin sudo <<'EOF'
#!/bin/sh
for a in "$@"; do
  case "$a" in -n|-nv) echo "sudo: a password is required" >&2; exit 1 ;; esac
done
sleep 900
EOF
    local t0=$SECONDS
    run lib_in_env -u ENVUP_PRIV -- 'printf %s "$ENVUP_PRIV"'
    local elapsed=$((SECONDS - t0))

    # No terminal to type a password into (bats), so there is no usable route.
    [ "$output" = none ]
    [ "$elapsed" -lt 15 ]
}

@test "caps: passwordless sudo is recognised as usable" {
    [ "$EUID" -ne 0 ] || skip "running as root; there is no sudo path to test"
    stub_bin sudo <<'EOF'
#!/bin/sh
while [ $# -gt 0 ]; do case "$1" in -*) shift ;; *) break ;; esac; done
[ $# -eq 0 ] && exit 0
exec "$@"
EOF
    run lib_in_env -u ENVUP_PRIV -- 'printf %s "$ENVUP_PRIV"'
    [ "$output" = sudo ]
}

@test "caps: no sudo binary at all means no route to root" {
    [ "$EUID" -ne 0 ] || skip "running as root; there is no sudo path to test"
    isolate_path      # note what is absent: sudo
    run lib_in_env -u ENVUP_PRIV -- 'printf %s "$ENVUP_PRIV"'
    [ "$output" = none ]
}

@test "caps: priv_run refuses rather than running the command unprivileged" {
    # Silently dropping the privilege would surface as a permission error from
    # somewhere deep inside a package manager, which is a much worse message.
    ENVUP_PRIV=none
    run priv_run true
    [ "$status" -eq 77 ]
    [[ "$output" == *"no route to it"* ]]
}

# ---- proxy passthrough (A6) ----------------------------------------------

@test "caps: a proxy in the environment makes privileged commands use sudo -E (A6)" {
    [ "$EUID" -ne 0 ] || skip "running as root; nothing is prefixed with sudo"
    stub_bin sudo <<'EOF'
#!/bin/sh
while [ $# -gt 0 ]; do case "$1" in -*) shift ;; *) break ;; esac; done
[ $# -eq 0 ] && exit 0
exec "$@"
EOF
    run lib_in_env -u ENVUP_PRIV -u ENVUP_PRIV_KEEP_ENV https_proxy=http://proxy:3128 \
        -- 'printf "%s|%s" "$ENVUP_PRIV_KEEP_ENV" "${ENVUP_PRIV_ARGV[*]}"'
    [ "$output" = "1|sudo -n -E" ]
}

@test "caps: sudoers refusing -E is reported, not silently ignored (A6)" {
    [ "$EUID" -ne 0 ] || skip "running as root; nothing is prefixed with sudo"
    # env_reset without SETENV: -E is rejected outright. Adding it anyway would
    # turn every package install into a hard failure.
    stub_bin sudo <<'EOF'
#!/bin/sh
for a in "$@"; do
  case "$a" in -E) echo "sudo: sorry, you are not allowed to preserve the environment" >&2; exit 1 ;; esac
done
while [ $# -gt 0 ]; do case "$1" in -*) shift ;; *) break ;; esac; done
[ $# -eq 0 ] && exit 0
exec "$@"
EOF
    run lib_in_env -u ENVUP_PRIV -u ENVUP_PRIV_KEEP_ENV https_proxy=http://proxy:3128 \
        -- 'printf "|%s|%s|" "$ENVUP_PRIV_KEEP_ENV" "${ENVUP_PRIV_ARGV[*]}"'
    [[ "$output" == *"|0|sudo -n|"* ]]      # -E dropped, sudo still usable
    [[ "$output" == *"refuses -E"* ]]       # and the user is told why
}

@test "caps: no proxy set means no -E (nothing to preserve)" {
    [ "$EUID" -ne 0 ] || skip "running as root; nothing is prefixed with sudo"
    stub_bin sudo <<'EOF'
#!/bin/sh
while [ $# -gt 0 ]; do case "$1" in -*) shift ;; *) break ;; esac; done
[ $# -eq 0 ] && exit 0
exec "$@"
EOF
    run lib_in_env -u ENVUP_PRIV -u ENVUP_PRIV_KEEP_ENV -u http_proxy -u https_proxy \
        -u HTTP_PROXY -u HTTPS_PROXY -u all_proxy -u ALL_PROXY \
        -- 'printf %s "${ENVUP_PRIV_ARGV[*]}"'
    [ "$output" = "sudo -n" ]
}

# ---- network -------------------------------------------------------------

@test "caps: ENVUP_OFFLINE=1 answers offline without touching the network" {
    # A stub that fails loudly if anything actually probes.
    stub_bin curl <<'EOF'
#!/bin/sh
echo "curl should not have been called" >&2
exit 99
EOF
    run lib_in_env -u ENVUP_NET ENVUP_OFFLINE=1 -- 'caps_net'
    [ "$output" = offline ]
}

@test "caps: a configured mirror wins over a reachable github (probe order)" {
    stub_bin curl <<'EOF'
#!/bin/sh
# Everything is reachable; the question is only which one gets chosen.
exit 0
EOF
    run lib_in_env -u ENVUP_NET ENVUP_GH_MIRROR=https://mirror.test -- 'caps_net'
    [ "$output" = mirror ]
}

@test "caps: an unreachable mirror falls through to a direct route" {
    stub_bin curl <<'EOF'
#!/bin/sh
for a in "$@"; do case "$a" in https://mirror.test*) exit 7 ;; esac; done
exit 0
EOF
    run lib_in_env -u ENVUP_NET ENVUP_GH_MIRROR=https://mirror.test -- 'caps_net'
    [ "$output" = direct ]
}

@test "caps: nothing reachable is offline, not a hang" {
    stub_bin curl <<'EOF'
#!/bin/sh
exit 7
EOF
    run lib_in_env -u ENVUP_NET -- 'caps_net'
    [ "$output" = offline ]
}

@test "net_fetch: refuses when offline instead of retrying into the void" {
    run net_fetch https://github.com/x/y/archive/main.tar.gz "$TEST_TMP/out"
    [ "$status" -eq 78 ]
    [ ! -e "$TEST_TMP/out" ]
}

@test "net_fetch: a dry run neither downloads nor probes the network" {
    stub_bin curl <<'EOF'
#!/bin/sh
echo "curl should not have been called" >&2
exit 99
EOF
    ENVUP_DRY_RUN=1 run net_fetch https://github.com/x/y "$TEST_TMP/out"
    [ "$status" -eq 0 ]
    [ ! -e "$TEST_TMP/out" ]
}

@test "net_fetch: the URL it reports is the rewritten one" {
    ENVUP_DRY_RUN=1 ENVUP_GH_MIRROR=https://mirror.test \
        run net_fetch https://github.com/x/y "$TEST_TMP/out"
    [[ "$output" == *"https://mirror.test/https://github.com/x/y"* ]]
}

# ---- summary -------------------------------------------------------------

@test "caps_summary: names every dimension a bug report needs" {
    run caps_summary
    local field
    for field in os= platform= distro= arch= libc= priv= pkg= host= shared_home= net=; do
        [[ "$output" == *"$field"* ]] || { echo "missing $field in: $output"; false; }
    done
}
