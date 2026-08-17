#!/usr/bin/env bats
# ripgrep, fd and delta — the three modules whose whole difficulty is naming.
#
# Every one of them goes by a different name depending on where you look: the
# package is ripgrep but the binary is rg, the package is git-delta but the
# binary is delta, and on Debian the package is fd-find and the binary is
# fdfind. Each mismatch has the same failure mode — the install "succeeds", the
# thing you typed is still not there — so each gets a test.

load '../test_helper'

setup() {
    common_setup
    # The engine sets these; sourcing a meta.sh on its own does not.
    NAME=""; VERIFY_BIN=""; PKG_NAMES=(); PKG_DEFAULT=""
}
teardown() { common_teardown; }

META() { printf '%s' "$REPO_ROOT/modules/$1/meta.sh"; }

# load_module <name> — pull in one module's declared data (and hooks) the way
# _engine_load would, but against the real repo rather than a fixture.
load_module() {
    # shellcheck source=/dev/null
    source "$(META "$1")"
    [[ -f "$REPO_ROOT/modules/$1/hooks.sh" ]] && source "$REPO_ROOT/modules/$1/hooks.sh"
    return 0
}

# pkg_name_on <family> — what this module's package is called there.
pkg_name_on() { ENVUP_PKG="$1" pkg_name; }

# ---- ripgrep -------------------------------------------------------------

@test "ripgrep: the engine checks for rg, not for ripgrep" {
    # VERIFY_BIN is what the engine runs to decide the install worked. Naming
    # the package here would make every install report success on a machine
    # where `rg` is not on PATH.
    load_module ripgrep
    [ "$VERIFY_BIN" = "rg" ]
}

@test "ripgrep: called ripgrep by every package manager" {
    load_module ripgrep
    local fam
    for fam in apt dnf pacman brew apk; do
        [ "$(pkg_name_on "$fam")" = "ripgrep" ]
    done
}

@test "ripgrep: linux/x86_64 gets the release asset, not the .deb" {
    load_module ripgrep
    ENVUP_OS=linux ENVUP_ARCH=x86_64 ENVUP_LIBC=glibc-2.35
    run _rg_pick
    [[ "$output" == *ripgrep-14.1.1-x86_64-unknown-linux-musl.tar.gz ]]
}

_rg_assets() {
    cat <<'EOF'
https://github.com/BurntSushi/ripgrep/releases/download/14.1.1/ripgrep-14.1.1-aarch64-unknown-linux-gnu.tar.gz
https://github.com/BurntSushi/ripgrep/releases/download/14.1.1/ripgrep-14.1.1-x86_64-apple-darwin.tar.gz
https://github.com/BurntSushi/ripgrep/releases/download/14.1.1/ripgrep-14.1.1-x86_64-pc-windows-msvc.zip
https://github.com/BurntSushi/ripgrep/releases/download/14.1.1/ripgrep-14.1.1-x86_64-unknown-linux-musl.tar.gz
https://github.com/BurntSushi/ripgrep/releases/download/14.1.1/ripgrep_14.1.1-1_amd64.deb
EOF
}
_rg_pick() { _rg_assets | _ghr_pick; }

# ---- fd ------------------------------------------------------------------

@test "fd: Debian and Fedora call the package fd-find" {
    # `fd` on Debian is an unrelated program that got there first. Without this
    # table apt is asked for a package that does not exist, and the module
    # falls all the way through to a download it did not need.
    load_module fd
    [ "$(pkg_name_on apt)" = "fd-find" ]
    [ "$(pkg_name_on dnf)" = "fd-find" ]
}

@test "fd: everyone else calls it fd" {
    load_module fd
    [ "$(pkg_name_on pacman)" = "fd" ]
    [ "$(pkg_name_on brew)" = "fd" ]
    [ "$(pkg_name_on apk)" = "fd" ]
}

@test "fd: fdfind counts as installed" {
    # Otherwise `apt-get install fd-find` succeeds, the engine looks for `fd`,
    # finds nothing, and downloads a second copy of the same program.
    load_module fd
    isolate_path
    stub_bin fdfind <<'EOF'
#!/bin/bash
echo "fd 8.7.0"
EOF
    run verify
    [ "$status" -eq 0 ]
}

@test "fd: neither name present means not installed" {
    load_module fd
    isolate_path
    rm -f "$STUB_BIN/fd" "$STUB_BIN/fdfind" "$ENVUP_LOCAL_BIN/fd"
    run verify
    [ "$status" -ne 0 ]
}

@test "fd: verify writes nothing — status and doctor only ask" {
    # verify() runs from `envup status` and `envup doctor`, which are read-only
    # commands. A predicate that repairs the machine as a side effect makes
    # those two lie about what they found.
    load_module fd
    isolate_path
    stub_bin fdfind <<'EOF'
#!/bin/bash
echo "fd 8.7.0"
EOF
    verify
    [ ! -e "$ENVUP_LOCAL_BIN/fd" ]
}

@test "fd: post_install puts the distro's binary on PATH under the name fd" {
    load_module fd
    isolate_path
    stub_bin fdfind <<'EOF'
#!/bin/bash
echo "fd 8.7.0"
EOF
    run post_install
    [ "$status" -eq 0 ]
    [ -L "$ENVUP_LOCAL_BIN/fd" ]
    [[ "$(readlink "$ENVUP_LOCAL_BIN/fd")" == *"/fdfind" ]]
}

@test "fd: a real fd is left exactly as it is" {
    load_module fd
    isolate_path
    stub_bin fd <<'EOF'
#!/bin/bash
echo "fd 10.2.0"
EOF
    stub_bin fdfind <<'EOF'
#!/bin/bash
echo "fd 8.7.0"
EOF
    run post_install
    [ "$status" -eq 0 ]
    [ ! -e "$ENVUP_LOCAL_BIN/fd" ]
}

@test "fd: dry-run creates nothing" {
    load_module fd
    isolate_path
    stub_bin fdfind <<'EOF'
#!/bin/bash
echo "fd 8.7.0"
EOF
    ENVUP_DRY_RUN=1 run post_install
    [ "$status" -eq 0 ]
    [ ! -e "$ENVUP_LOCAL_BIN/fd" ]
}

@test "fd: uninstall takes back the shim it created" {
    load_module fd
    mkdir -p "$ENVUP_LOCAL_BIN"
    ln -sf /usr/bin/fdfind "$ENVUP_LOCAL_BIN/fd"
    run post_uninstall
    [ "$status" -eq 0 ]
    [ ! -e "$ENVUP_LOCAL_BIN/fd" ]
}

@test "fd: uninstall does not touch an fd that is not our shim" {
    # A binary someone else put there — a release we downloaded, a build of
    # their own. envup only ever removes what envup created.
    load_module fd
    mkdir -p "$ENVUP_LOCAL_BIN"
    printf '#!/bin/sh\n' > "$ENVUP_LOCAL_BIN/fd"; chmod +x "$ENVUP_LOCAL_BIN/fd"
    run post_uninstall
    [ "$status" -eq 0 ]
    [ -f "$ENVUP_LOCAL_BIN/fd" ]
}

@test "fd: the 'fd-v10' asset name is not mistaken for a sibling product" {
    # _ghr_wrong_artifact demotes assets whose name is <tool>-<something else>
    # (atuin-server, for instance). fd's own assets are fd-v10.2.0-..., which
    # has exactly that shape — the version check is what saves them.
    load_module fd
    ENVUP_OS=linux ENVUP_ARCH=x86_64 ENVUP_LIBC=glibc-2.35
    run _fd_pick
    [[ "$output" == *fd-v10.2.0-x86_64-unknown-linux-gnu.tar.gz ]]
}

_fd_assets() {
    cat <<'EOF'
https://github.com/sharkdp/fd/releases/download/v10.2.0/fd-v10.2.0-aarch64-unknown-linux-gnu.tar.gz
https://github.com/sharkdp/fd/releases/download/v10.2.0/fd-v10.2.0-x86_64-apple-darwin.tar.gz
https://github.com/sharkdp/fd/releases/download/v10.2.0/fd-v10.2.0-x86_64-unknown-linux-gnu.tar.gz
https://github.com/sharkdp/fd/releases/download/v10.2.0/fd-v10.2.0-x86_64-unknown-linux-musl.tar.gz
https://github.com/sharkdp/fd/releases/download/v10.2.0/fd_10.2.0_amd64.deb
EOF
}
_fd_pick() { _fd_assets | _ghr_pick; }

# ---- delta ---------------------------------------------------------------

@test "delta: the package is git-delta nearly everywhere" {
    load_module delta
    [ "$(pkg_name_on apt)" = "git-delta" ]
    [ "$(pkg_name_on dnf)" = "git-delta" ]
    [ "$(pkg_name_on pacman)" = "git-delta" ]
    [ "$(pkg_name_on brew)" = "git-delta" ]
    [ "$(pkg_name_on apk)" = "delta" ]
}

@test "delta: the binary is still delta" {
    load_module delta
    [ "$VERIFY_BIN" = "delta" ]
}

@test "delta: git is installed first" {
    # Not decoration: hooks.sh reaches into the git module to rewrite the
    # generated config, and that file has to exist by then.
    mkdir -p "$ENVUP_HOME/modules"
    ln -sfn "$REPO_ROOT/modules/git"   "$ENVUP_HOME/modules/git"
    ln -sfn "$REPO_ROOT/modules/delta" "$ENVUP_HOME/modules/delta"
    run resolve_order delta
    [ "$output" = "git
delta" ]
}

@test "delta: installing it turns on git's pager" {
    # git ran first, when the honest answer to "is delta here?" was no. Nothing
    # would ever revisit that answer without this hook.
    mkdir -p "$ENVUP_HOME/modules"
    ln -sfn "$REPO_ROOT/modules/git" "$ENVUP_HOME/modules/git"
    stub_bin delta <<'EOF'
#!/bin/bash
echo "delta 0.18.2"
EOF
    printf '# stale\n' > "$HOME/.gitconfig.envup"

    load_module delta
    run post_install
    [ "$status" -eq 0 ]
    grep -q '\[pager\]' "$HOME/.gitconfig.envup"
    grep -q 'diffFilter = .*delta --color-only' "$HOME/.gitconfig.envup"
}

@test "delta: git's own hooks do not leak into delta's" {
    # hooks.sh sources modules/git/hooks.sh, which defines post_install. If that
    # happened in this shell, the engine's next call to post_install would run
    # git's — and delta would silently reconfigure git's identity file instead.
    mkdir -p "$ENVUP_HOME/modules"
    ln -sfn "$REPO_ROOT/modules/git" "$ENVUP_HOME/modules/git"
    stub_bin delta <<'EOF'
#!/bin/bash
echo "delta 0.18.2"
EOF
    load_module delta
    post_install
    # git's post_install creates ~/.gitconfig.local; delta's must not.
    [ ! -e "$HOME/.gitconfig.local" ]
}

@test "delta: no git module means a warning, not a failed install" {
    rm -rf "$ENVUP_HOME/modules/git"
    load_module delta
    run post_install
    [ "$status" -eq 0 ]
}

@test "delta: the .deb is skipped in favour of the tarball" {
    load_module delta
    ENVUP_OS=linux ENVUP_ARCH=x86_64 ENVUP_LIBC=glibc-2.35
    run _delta_pick
    [[ "$output" == *delta-0.18.2-x86_64-unknown-linux-gnu.tar.gz ]]
}

_delta_assets() {
    cat <<'EOF'
https://github.com/dandavison/delta/releases/download/0.18.2/delta-0.18.2-aarch64-unknown-linux-gnu.tar.gz
https://github.com/dandavison/delta/releases/download/0.18.2/delta-0.18.2-x86_64-apple-darwin.tar.gz
https://github.com/dandavison/delta/releases/download/0.18.2/delta-0.18.2-x86_64-unknown-linux-gnu.tar.gz
https://github.com/dandavison/delta/releases/download/0.18.2/delta-0.18.2-x86_64-unknown-linux-musl.tar.gz
https://github.com/dandavison/delta/releases/download/0.18.2/git-delta_0.18.2_amd64.deb
https://github.com/dandavison/delta/releases/download/0.18.2/git-delta-musl_0.18.2_amd64.deb
EOF
}
_delta_pick() { _delta_assets | _ghr_pick; }

# ---- the profile ---------------------------------------------------------

@test "the standard profile installs all three" {
    local p="$REPO_ROOT/profiles/standard.sh"
    MODULES=()
    ENVUP_HOME="$REPO_ROOT" load_profile standard
    [[ " ${MODULES[*]} " == *" ripgrep "* ]]
    [[ " ${MODULES[*]} " == *" fd "* ]]
    [[ " ${MODULES[*]} " == *" delta "* ]]
    [[ -f "$p" ]]
}

@test "the standard profile still resolves into a valid order" {
    MODULES=()
    ENVUP_HOME="$REPO_ROOT" load_profile standard
    run env ENVUP_HOME="$REPO_ROOT" bash -c \
        "source '$REPO_ROOT/lib.sh'; load_profile standard >/dev/null; resolve_order \"\${MODULES[@]}\""
    [ "$status" -eq 0 ]
    # zsh before zoxide (which depends on it), git before delta.
    [[ "$output" == *zsh* ]]
    local order="$output"
    [[ "${order%%delta*}" == *git* ]]
    [[ "${order%%zoxide*}" == *zsh* ]]
}
