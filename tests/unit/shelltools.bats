#!/usr/bin/env bats
# eza, bat and direnv — the three tools the shell config has always called for
# and never had.
#
# All three were referenced behind an existence guard: `(( $+commands[eza] ))`
# in the alias slice, the same for bat, and `eval "$(direnv hook zsh)"` in the
# tools slice. A guard that is always false is indistinguishable from a feature
# nobody wanted, which is why this went unnoticed through two releases.
#
# What is actually hard about each is different, so the tests are: bat has two
# names (like fd), eza has two *builds* (one of them crippled), and direnv ships
# a bare binary rather than an archive.

load '../test_helper'

setup() {
    common_setup
    # The engine sets these; sourcing a meta.sh on its own does not.
    NAME=""; VERIFY_BIN=""; PKG_NAMES=(); PKG_DEFAULT=""; GH_ASSET_AVOID=()
}
teardown() { common_teardown; }

load_module() {
    # shellcheck source=/dev/null
    source "$REPO_ROOT/modules/$1/meta.sh"
    [[ -f "$REPO_ROOT/modules/$1/hooks.sh" ]] && source "$REPO_ROOT/modules/$1/hooks.sh"
    return 0
}

pkg_name_on() { ENVUP_PKG="$1" pkg_name; }

# _pick_from <url>... — the asset _ghr_pick chooses out of exactly these.
_pick_from() { printf '%s\n' "$@" | _ghr_pick; }
_eza_pick()    { _eza_assets    | _ghr_pick; }
_bat_pick()    { _bat_assets    | _ghr_pick; }
_direnv_pick() { _direnv_assets | _ghr_pick; }

# ---- eza -----------------------------------------------------------------
# The interesting part is that upstream ships two Linux builds per platform and
# one of them is missing a feature the config uses.

_eza_assets() {
    cat <<'EOF'
https://github.com/eza-community/eza/releases/download/v0.21.0/eza_aarch64-unknown-linux-gnu.tar.gz
https://github.com/eza-community/eza/releases/download/v0.21.0/eza_aarch64-unknown-linux-gnu_no_libgit.tar.gz
https://github.com/eza-community/eza/releases/download/v0.21.0/eza.exe_x86_64-pc-windows-gnu.zip
https://github.com/eza-community/eza/releases/download/v0.21.0/eza_x86_64-unknown-linux-gnu.tar.gz
https://github.com/eza-community/eza/releases/download/v0.21.0/eza_x86_64-unknown-linux-gnu_no_libgit.tar.gz
https://github.com/eza-community/eza/releases/download/v0.21.0/eza_x86_64-unknown-linux-musl.tar.gz
https://github.com/eza-community/eza/releases/download/v0.21.0/completions-0.21.0.tar.gz
https://github.com/eza-community/eza/releases/download/v0.21.0/man-0.21.0.tar.gz
EOF
}

@test "eza: the full build wins over _no_libgit" {
    # `ll` is `eza -la --git`. The no_libgit build has --git compiled out, so it
    # installs, runs, reports a normal --version, and quietly shows a column of
    # dashes where the git status belongs.
    load_module eza
    ENVUP_OS=linux ENVUP_ARCH=x86_64 ENVUP_LIBC=glibc-2.35
    run _eza_pick
    [[ "$output" == *eza_x86_64-unknown-linux-gnu.tar.gz ]]
}

@test "eza: which build wins does not depend on the machine's locale" {
    # The two builds score identically on os, arch, libc and format, so before
    # GH_ASSET_AVOID the winner was whichever came first — and the list is
    # `sort`ed, which under en_US.UTF-8 ignores the underscore and puts
    # _no_libgit first, while under C it does not. Two machines, two binaries,
    # no way to tell from the outside.
    load_module eza
    ENVUP_OS=linux ENVUP_ARCH=x86_64 ENVUP_LIBC=glibc-2.35
    local first
    first=$(printf '%s\n' \
        "https://github.com/eza-community/eza/releases/download/v0.21.0/eza_x86_64-unknown-linux-gnu_no_libgit.tar.gz" \
        "https://github.com/eza-community/eza/releases/download/v0.21.0/eza_x86_64-unknown-linux-gnu.tar.gz" \
        | _ghr_pick)
    [[ "$first" == *"/eza_x86_64-unknown-linux-gnu.tar.gz" ]]
}

@test "eza: a reduced build still beats no build at all" {
    # The aarch64 musl case, and any future platform where upstream only
    # publishes the cut-down one. A penalty, not a veto.
    load_module eza
    ENVUP_OS=linux ENVUP_ARCH=aarch64 ENVUP_LIBC=musl
    run _pick_from "https://github.com/eza-community/eza/releases/download/v0.21.0/eza_aarch64-unknown-linux-gnu_no_libgit.tar.gz"
    [ "$status" -eq 0 ]
    [[ "$output" == *no_libgit.tar.gz ]]
}

@test "eza: the completions and man tarballs are not mistaken for the program" {
    load_module eza
    ENVUP_OS=linux ENVUP_ARCH=x86_64 ENVUP_LIBC=glibc-2.35
    run _eza_pick
    [[ "$output" != *completions* ]]
    [[ "$output" != *man-0.21.0* ]]
}

@test "eza: musl machines get the musl build" {
    load_module eza
    ENVUP_OS=linux ENVUP_ARCH=x86_64 ENVUP_LIBC=musl
    run _eza_pick
    [[ "$output" == *eza_x86_64-unknown-linux-musl.tar.gz ]]
}

@test "eza: macOS has no release asset, so the package manager is the route" {
    # Upstream publishes Linux and Windows only and points Mac users at brew.
    # The provider must decline rather than install a Linux binary.
    load_module eza
    ENVUP_OS=macos ENVUP_ARCH=aarch64 ENVUP_LIBC=""
    run _eza_pick
    [ "$status" -ne 0 ]
    [ "$(pkg_name_on brew)" = "eza" ]
    [[ " ${PROVIDERS[*]} " == *" system "* ]]
}

@test "eza: GH_ASSET_AVOID does not leak into the next module" {
    # The engine loads modules one after another in a single process. An array
    # left set by eza would silently demote assets for whatever came next.
    grep -q 'GH_ASSET_AVOID=()' "$REPO_ROOT/lib/engine.sh"
}

# ---- bat -----------------------------------------------------------------
# Debian's bat binary is batcat, the same way its fd binary is fdfind.

@test "bat: the package is called bat even on Debian" {
    # Only the binary is renamed, so there is nothing for PKG_NAMES to fix —
    # and adding an entry would break apt.
    load_module bat
    local fam
    for fam in apt dnf pacman brew apk; do
        [ "$(pkg_name_on "$fam")" = "bat" ]
    done
}

@test "bat: batcat counts as installed" {
    load_module bat
    isolate_path
    stub_bin batcat <<'EOF'
#!/bin/bash
echo "bat 0.24.0"
EOF
    run verify
    [ "$status" -eq 0 ]
}

@test "bat: neither name present means not installed" {
    load_module bat
    isolate_path
    rm -f "$STUB_BIN/bat" "$STUB_BIN/batcat" "$ENVUP_LOCAL_BIN/bat"
    run verify
    [ "$status" -ne 0 ]
}

@test "bat: verify writes nothing — status and doctor only ask" {
    load_module bat
    isolate_path
    stub_bin batcat <<'EOF'
#!/bin/bash
echo "bat 0.24.0"
EOF
    verify
    [ ! -e "$ENVUP_LOCAL_BIN/bat" ]
}

@test "bat: post_install puts the distro's binary on PATH under the name bat" {
    load_module bat
    isolate_path
    stub_bin batcat <<'EOF'
#!/bin/bash
echo "bat 0.24.0"
EOF
    run post_install
    [ "$status" -eq 0 ]
    [ -L "$ENVUP_LOCAL_BIN/bat" ]
    [[ "$(readlink "$ENVUP_LOCAL_BIN/bat")" == *"/batcat" ]]
}

@test "bat: a real bat is left exactly as it is" {
    load_module bat
    isolate_path
    stub_bin bat <<'EOF'
#!/bin/bash
echo "bat 0.25.0"
EOF
    stub_bin batcat <<'EOF'
#!/bin/bash
echo "bat 0.24.0"
EOF
    run post_install
    [ "$status" -eq 0 ]
    [ ! -e "$ENVUP_LOCAL_BIN/bat" ]
}

@test "bat: dry-run creates nothing" {
    load_module bat
    isolate_path
    stub_bin batcat <<'EOF'
#!/bin/bash
echo "bat 0.24.0"
EOF
    ENVUP_DRY_RUN=1 run post_install
    [ "$status" -eq 0 ]
    [ ! -e "$ENVUP_LOCAL_BIN/bat" ]
}

@test "bat: uninstall takes back the shim it created" {
    load_module bat
    mkdir -p "$ENVUP_LOCAL_BIN"
    ln -sf /usr/bin/batcat "$ENVUP_LOCAL_BIN/bat"
    run post_uninstall
    [ "$status" -eq 0 ]
    [ ! -e "$ENVUP_LOCAL_BIN/bat" ]
}

@test "bat: uninstall does not touch a bat that is not our shim" {
    load_module bat
    mkdir -p "$ENVUP_LOCAL_BIN"
    printf '#!/bin/sh\n' > "$ENVUP_LOCAL_BIN/bat"; chmod +x "$ENVUP_LOCAL_BIN/bat"
    run post_uninstall
    [ "$status" -eq 0 ]
    [ -f "$ENVUP_LOCAL_BIN/bat" ]
}

@test "bat: the .deb variants are skipped in favour of the tarball" {
    # sharkdp publishes bat_*.deb and bat-musl_*.deb alongside the tarballs; a
    # .deb needs root and dpkg, which is the situation this provider exists for.
    load_module bat
    ENVUP_OS=linux ENVUP_ARCH=x86_64 ENVUP_LIBC=glibc-2.35
    run _bat_pick
    [[ "$output" == *bat-v0.26.1-x86_64-unknown-linux-gnu.tar.gz ]]
}

_bat_assets() {
    cat <<'EOF'
https://github.com/sharkdp/bat/releases/download/v0.26.1/bat_0.26.1_amd64.deb
https://github.com/sharkdp/bat/releases/download/v0.26.1/bat-musl_0.26.1_musl-linux-amd64.deb
https://github.com/sharkdp/bat/releases/download/v0.26.1/bat-v0.26.1-aarch64-unknown-linux-gnu.tar.gz
https://github.com/sharkdp/bat/releases/download/v0.26.1/bat-v0.26.1-x86_64-apple-darwin.tar.gz
https://github.com/sharkdp/bat/releases/download/v0.26.1/bat-v0.26.1-x86_64-pc-windows-msvc.zip
https://github.com/sharkdp/bat/releases/download/v0.26.1/bat-v0.26.1-x86_64-unknown-linux-gnu.tar.gz
https://github.com/sharkdp/bat/releases/download/v0.26.1/bat-v0.26.1-x86_64-unknown-linux-musl.tar.gz
EOF
}

@test "bat: 'bat-musl' is not read as a different product" {
    # _ghr_wrong_artifact demotes <tool>-<something>; bat-musl has that shape.
    # It only ever appears as a .deb, so the filter gets it first — but if that
    # ever changes, a musl machine should still take it.
    load_module bat
    ENVUP_OS=linux ENVUP_ARCH=x86_64 ENVUP_LIBC=musl
    run _bat_pick
    [[ "$output" == *bat-v0.26.1-x86_64-unknown-linux-musl.tar.gz ]]
}

# ---- direnv --------------------------------------------------------------
# One Go binary, published bare — no tarball to unpack.

_direnv_assets() {
    cat <<'EOF'
https://github.com/direnv/direnv/releases/download/v2.37.1/direnv.darwin-amd64
https://github.com/direnv/direnv/releases/download/v2.37.1/direnv.darwin-arm64
https://github.com/direnv/direnv/releases/download/v2.37.1/direnv.linux-386
https://github.com/direnv/direnv/releases/download/v2.37.1/direnv.linux-amd64
https://github.com/direnv/direnv/releases/download/v2.37.1/direnv.linux-arm64
https://github.com/direnv/direnv/releases/download/v2.37.1/direnv.linux-mips64
https://github.com/direnv/direnv/releases/download/v2.37.1/direnv.linux-ppc64le
https://github.com/direnv/direnv/releases/download/v2.37.1/direnv.windows-amd64
EOF
}

@test "direnv: a bare binary is a valid release asset" {
    load_module direnv
    ENVUP_OS=linux ENVUP_ARCH=x86_64 ENVUP_LIBC=glibc-2.35
    run _direnv_pick
    [ "$status" -eq 0 ]
    [[ "$output" == *direnv.linux-amd64 ]]
}

@test "direnv: the other 64-bit architectures are not mistaken for x86_64" {
    # linux-mips64 and linux-ppc64le both end in 64 and both would install
    # cleanly and then refuse to execute.
    load_module direnv
    ENVUP_OS=linux ENVUP_ARCH=x86_64 ENVUP_LIBC=glibc-2.35
    run _direnv_pick
    [[ "$output" != *mips* ]]
    [[ "$output" != *ppc* ]]
}

@test "direnv: an Apple Silicon Mac gets darwin-arm64" {
    load_module direnv
    ENVUP_OS=macos ENVUP_ARCH=aarch64 ENVUP_LIBC=""
    run _direnv_pick
    [[ "$output" == *direnv.darwin-arm64 ]]
}

@test "direnv: depends on zsh, because the hook is where it lives" {
    # Installed without the shell hook it is a binary that never runs. The
    # dependency is also what orders zsh first, so the hook is on disk when the
    # next login shell starts.
    load_module direnv
    [[ " ${DEPENDS[*]} " == *" zsh "* ]]
}

@test "direnv: the allow-list is not something clean may remove" {
    # ~/.local/share/direnv records which .envrc files you decided to trust.
    # Deleting it silently re-blocks every project you have ever allowed.
    load_module direnv
    [ "${#CLEAN_PATHS[@]}" -eq 0 ]
}

@test "direnv: the shell hook is actually wired up" {
    grep -q 'direnv hook zsh' "$REPO_ROOT/modules/zsh/files/.zshrc.d/50-tools.zsh"
}

# ---- the profile ---------------------------------------------------------

@test "the standard profile installs all three" {
    MODULES=()
    ENVUP_HOME="$REPO_ROOT" load_profile standard
    [[ " ${MODULES[*]} " == *" eza "* ]]
    [[ " ${MODULES[*]} " == *" bat "* ]]
    [[ " ${MODULES[*]} " == *" direnv "* ]]
}

@test "the aliases these modules exist for are still there" {
    # If someone removes the alias, the module becomes a download with no
    # purpose — and the failure is silent in that direction too.
    local a="$REPO_ROOT/modules/zsh/files/.zshrc.d/60-alias.zsh"
    grep -q 'commands\[eza\]' "$a"
    grep -q 'commands\[bat\]' "$a"
    grep -q 'commands\[batcat\]' "$a"
}
