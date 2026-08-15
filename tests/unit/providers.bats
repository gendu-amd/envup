#!/usr/bin/env bats
# The install routes (lib/providers/*.sh). Two things matter here:
#   - a route that does not exist on this machine must decline, not fail, so the
#     chain keeps walking (this is what makes a no-root server work at all);
#   - github_release must pick the right asset, because picking the wrong one
#     produces a binary that installs cleanly and then dies at first run with
#     "GLIBC_2.32 not found" or "cannot execute binary file".

load '../test_helper'

setup() { common_setup; NAME=fixture; VERIFY_BIN=fixture; }
teardown() { common_teardown; }

# ---- system --------------------------------------------------------------

@test "provider_system: declines when the distro has no such package" {
    # "-" is how meta.sh says "not packaged here". Declining (79) rather than
    # failing is what lets the chain reach github_release without a scary error.
    PKG_NAMES=(); PKG_DEFAULT="-"
    run provider_system
    [ "$status" -eq "$ENVUP_RC_UNAVAIL" ]
}

@test "provider_system: declines on a machine with no route to root" {
    PKG_NAMES=(); PKG_DEFAULT="fixture"
    ENVUP_PRIV=none run provider_system
    [ "$status" -eq "$ENVUP_RC_UNAVAIL" ]
}

# ---- manual --------------------------------------------------------------

@test "provider_manual: returns 'degraded' and says what a human should do" {
    MANUAL_HINT="ask an admin for the fixture package"
    run provider_manual
    [ "$status" -eq "$ENVUP_RC_DEGRADED" ]
    [[ "$output" == *"ask an admin"* ]]
}

@test "provider_manual: without a hint it still names the package and the manager" {
    MANUAL_HINT=""; PKG_NAMES=(); PKG_DEFAULT="fixture-pkg"
    run provider_manual
    [ "$status" -eq "$ENVUP_RC_DEGRADED" ]
    [[ "$output" == *"fixture-pkg"* ]]
}

# ---- github_release: asset selection ------------------------------------

_assets() {
    cat <<'EOF'
https://github.com/o/r/releases/download/v1/tool-v1-x86_64-unknown-linux-gnu.tar.gz
https://github.com/o/r/releases/download/v1/tool-v1-x86_64-unknown-linux-musl.tar.gz
https://github.com/o/r/releases/download/v1/tool-v1-aarch64-unknown-linux-gnu.tar.gz
https://github.com/o/r/releases/download/v1/tool-v1-x86_64-apple-darwin.tar.gz
https://github.com/o/r/releases/download/v1/tool-v1-aarch64-apple-darwin.tar.gz
https://github.com/o/r/releases/download/v1/tool-v1-x86_64-linux.tar.gz.sha256
https://github.com/o/r/releases/download/v1/tool_1_amd64.deb
https://github.com/o/r/releases/download/v1/tool-1.x86_64.rpm
https://github.com/o/r/releases/download/v1/source.tar.gz
EOF
}

# `run bash -c ...` would start a child shell that has never sourced lib.sh, so
# _ghr_pick would not exist there. Keep the pick in this process.
pick()     { _assets | _ghr_pick; }
pick_one() { printf '%s\n' "$1" | _ghr_pick; }
pick_two() { printf '%s\n%s\n' "$1" "$2" | _ghr_pick; }

@test "_ghr_pick: matches OS and architecture" {
    ENVUP_OS=linux ENVUP_ARCH=aarch64 ENVUP_LIBC=glibc-2.35
    run pick
    [[ "$output" == *aarch64-unknown-linux-gnu.tar.gz ]]
}

@test "_ghr_pick: macos/arm64 does not get handed a linux build" {
    ENVUP_OS=macos ENVUP_ARCH=aarch64 ENVUP_LIBC=""
    run pick
    [[ "$output" == *aarch64-apple-darwin.tar.gz ]]
}

@test "_ghr_pick: a musl machine gets the musl build, not the glibc one" {
    # The failure this prevents is not a failed install — it is a binary that
    # installs fine and then cannot start, on Alpine or on an old CentOS.
    ENVUP_OS=linux ENVUP_ARCH=x86_64 ENVUP_LIBC=musl
    run pick
    [[ "$output" == *x86_64-unknown-linux-musl.tar.gz ]]
}

@test "_ghr_pick: skips checksums, distro packages and source tarballs" {
    ENVUP_OS=linux ENVUP_ARCH=x86_64 ENVUP_LIBC=glibc-2.35
    run pick
    [[ "$output" != *.sha256 ]]
    [[ "$output" != *.deb ]]
    [[ "$output" != *.rpm ]]
    [[ "$output" != *source* ]]
}

@test "_ghr_pick: an architecture with no asset is a miss, not a wrong guess" {
    # Silently installing an x86_64 binary on a riscv box would be worse than
    # returning nothing: the chain can fall through to another provider.
    ENVUP_OS=linux ENVUP_ARCH=riscv64 ENVUP_LIBC=glibc-2.35
    run pick
    [ "$status" -ne 0 ]
    [ -z "$output" ]
}

@test "_ghr_pick: 'arm64' and 'aarch64' name the same machine" {
    ENVUP_OS=macos ENVUP_ARCH=aarch64 ENVUP_LIBC=""
    run pick_one "https://github.com/o/r/releases/download/v1/tool-darwin-arm64.zip"
    [ "$status" -eq 0 ]
    [[ "$output" == *arm64.zip ]]
}

@test "_ghr_pick: a sibling product in the same release does not win" {
    # atuin ships the client and the server side by side. They score identically
    # on os/arch/format, so the tie used to break alphabetically — and
    # atuin-server sorts first. It installed cleanly and was the wrong binary.
    VERIFY_BIN=atuin; GH_BIN=""
    ENVUP_OS=linux ENVUP_ARCH=x86_64 ENVUP_LIBC=glibc-2.35
    run pick_two \
        "https://github.com/atuinsh/atuin/releases/download/v18/atuin-server-x86_64-unknown-linux-gnu.tar.gz" \
        "https://github.com/atuinsh/atuin/releases/download/v18/atuin-x86_64-unknown-linux-gnu.tar.gz"
    [[ "$output" == *"/atuin-x86_64-unknown-linux-gnu.tar.gz" ]]
}

@test "_ghr_pick: a sibling product still wins if it is the only candidate" {
    # The penalty must not turn into a rejection: some repos only ever ship
    # <name>-cli-<platform>, and refusing it would lose the tool entirely.
    VERIFY_BIN=tool; GH_BIN=""
    ENVUP_OS=linux ENVUP_ARCH=x86_64 ENVUP_LIBC=glibc-2.35
    run pick_one "https://github.com/o/r/releases/download/v1/tool-cli-x86_64-linux.tar.gz"
    [ "$status" -eq 0 ]
    [[ "$output" == *tool-cli-x86_64-linux.tar.gz ]]
}

@test "_ghr_pick: a version or a platform right after the name is not a sibling" {
    VERIFY_BIN=fzf; GH_BIN=""
    ENVUP_OS=linux ENVUP_ARCH=x86_64 ENVUP_LIBC=glibc-2.35
    run pick_one "https://github.com/junegunn/fzf/releases/download/v0.74.2/fzf-0.74.2-linux_amd64.tar.gz"
    [[ "$output" == *fzf-0.74.2-linux_amd64.tar.gz ]]

    VERIFY_BIN=nvim
    run pick_one "https://github.com/neovim/neovim/releases/download/v0.12.4/nvim-linux-x86_64.tar.gz"
    [[ "$output" == *nvim-linux-x86_64.tar.gz ]]
}

# ---- github_release: version pinning ------------------------------------

@test "_ghr_pin: reads the tag for a module out of versions.lock" {
    cat > "$ENVUP_HOME/versions.lock" <<'EOF'
# comment line
zoxide   v0.9.4
atuin    v18.3.0
EOF
    run _ghr_pin atuin
    [ "$status" -eq 0 ]
    [ "$output" = "v18.3.0" ]
}

@test "_ghr_pin: an unpinned module reports no pin (latest wins)" {
    printf 'zoxide v0.9.4\n' > "$ENVUP_HOME/versions.lock"
    run _ghr_pin nvim
    [ "$status" -ne 0 ]
}

@test "_ghr_pin: no versions.lock at all is not an error" {
    rm -f "$ENVUP_HOME/versions.lock"
    run _ghr_pin zoxide
    [ "$status" -ne 0 ]
    [ -z "$output" ]
}

# ---- declining routes ----------------------------------------------------

@test "provider_github_release: declines when offline instead of hanging" {
    GH_REPO="o/r"
    ENVUP_NET=offline run provider_github_release
    [ "$status" -eq "$ENVUP_RC_UNAVAIL" ]
}

@test "provider_git: declines when offline" {
    GIT_URL="https://github.com/o/r.git"
    ENVUP_NET=offline run provider_git
    [ "$status" -eq "$ENVUP_RC_UNAVAIL" ]
}

@test "provider_script: declines when offline" {
    SCRIPT_URL="https://example.com/install.sh"
    ENVUP_NET=offline run provider_script
    [ "$status" -eq "$ENVUP_RC_UNAVAIL" ]
}

@test "provider_github_release: dry-run reports the plan and installs nothing" {
    GH_REPO="o/r"
    ENVUP_DRY_RUN=1 run provider_github_release
    [ "$status" -eq 0 ]
    [[ "$output" == *"[dry-run]"* ]]
    [ ! -e "$ENVUP_LOCAL_BIN/fixture" ]
}

# ---- rc-file shielding ---------------------------------------------------

@test "_script_shield: an envup-owned rc file is swapped aside and restored" {
    # Vendor installers append their init lines to whatever rc files they find.
    # ~/.zshrc is a symlink into the repo, so an unshielded installer commits
    # its changes to version control on your behalf.
    mkdir -p "$ENVUP_HOME/files"; printf 'original\n' > "$ENVUP_HOME/files/zshrc"
    safe_link "files/zshrc" "$HOME/.zshrc"

    _script_shield
    [ ! -L "$HOME/.zshrc" ]              # a plain empty file for the installer
    printf 'INSTALLER JUNK\n' >> "$HOME/.zshrc"

    _script_unshield
    [ -L "$HOME/.zshrc" ]
    [ "$(cat "$HOME/.zshrc")" = original ]
    [ "$(cat "$ENVUP_HOME/files/zshrc")" = original ]
}

@test "_script_shield: an rc file envup does not own is left alone" {
    printf 'not ours\n' > "$HOME/.bashrc"
    _script_shield
    [ -f "$HOME/.bashrc" ]
    [ "$(cat "$HOME/.bashrc")" = "not ours" ]
    [ ! -e "$HOME/.bashrc.envup-bak" ]
    _script_unshield
}
