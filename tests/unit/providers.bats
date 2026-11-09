#!/usr/bin/env bats
# Provider fallback and platform-specific release selection.

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
place_tree_nounset() { set -u; _ghr_place_tree "$1"; }

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

@test "nvim selects its compatible release on old glibc only" {
    source "$REPO_ROOT/modules/nvim/meta.sh"
    source "$REPO_ROOT/modules/nvim/hooks.sh"

    ENVUP_LIBC=glibc-2.32 GH_TAG=""
    pre_install
    [ "$GH_TAG" = v0.10.4 ]

    ENVUP_LIBC=glibc-2.34 GH_TAG=""
    pre_install
    [ -z "$GH_TAG" ]

    ENVUP_LIBC=darwin GH_TAG=""
    pre_install
    [ -z "$GH_TAG" ]
}

# ---- the lockfile this repo actually ships -------------------------------
#
# The mechanism above is tested against fixtures; these two check the file. A
# lockfile is only worth having if it is complete: with six of ten modules
# pinned, the fleet agrees about most things, and the tools it disagrees about
# are the ones nobody chose — which is a harder problem than not pinning at all.

_gh_modules() {
    local m
    for m in "$REPO_ROOT"/modules/*/meta.sh; do
        grep -q '^PROVIDERS=.*github_release' "$m" && basename "$(dirname "$m")"
    done
}

_lock_modules() {
    grep -vE '^\s*(#|$)' "$REPO_ROOT/versions.lock" | awk '{print $1}'
}

@test "every module that installs from a GitHub release is pinned" {
    local m missing=()
    while read -r m; do
        [[ -n "$m" ]] || continue
        _lock_modules | grep -qx "$m" || missing+=("$m")
    done < <(_gh_modules)
    [ "${#missing[@]}" -eq 0 ] || {
        echo "not in versions.lock: ${missing[*]}"; return 1
    }
}

@test "versions.lock pins nothing that no longer exists" {
    # The other direction: a module gets deleted or switches provider and its
    # line stays, pinning something to a tag nobody reads.
    local m stale=()
    while read -r m; do
        [[ -n "$m" ]] || continue
        _gh_modules | grep -qx "$m" || stale+=("$m")
    done < <(_lock_modules)
    [ "${#stale[@]}" -eq 0 ] || {
        echo "pinned but no such github_release module: ${stale[*]}"; return 1
    }
}

@test "every pinned tag contains a release version" {
    # Tags stay verbatim: upstream uses 15.2.0, v0.26.1 and jq-1.8.2.
    # What is never right is a bare word or a URL.
    local line
    while read -r line; do
        [[ -n "$line" ]] || continue
        [[ "$line" =~ ^[a-z0-9_-]+[[:space:]]+[a-z0-9_-]*[0-9]+\.[0-9]+(\.[0-9]+)?[a-z0-9.-]*$ ]] || {
            echo "malformed lockfile line: $line"; return 1
        }
    done < <(grep -vE '^\s*(#|$)' "$REPO_ROOT/versions.lock" | sed 's/#.*//')
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

@test "release install reports when the user's PATH still selects another tool" {
    GH_REPO=o/r GH_TAG=v2.0 ENVUP_OS=linux ENVUP_ARCH=x86_64 ENVUP_LIBC=glibc
    stub_bin fixture <<'EOF'
#!/bin/sh
echo fixture 1.0
EOF
    net_online() { return 0; }
    _ghr_urls() { printf 'v2.0\nhttps://github.com/o/r/releases/download/v2.0/fixture-linux-x86_64\n'; }
    net_fetch() { printf '#!/bin/sh\necho fixture 2.0\n' > "$2"; }
    net_check_asset() { return 0; }
    run provider_github_release
    [ "$status" -eq 0 ]
    [[ "$output" == *"user PATH resolves fixture to $STUB_BIN/fixture"* ]]
    [ "$("$ENVUP_LOCAL_BIN/fixture")" = 'fixture 2.0' ]
    [ "$(bin_version fixture)" = 1.0 ]
}

@test "_ghr_place_bins: installs every binary from one archive" {
    mkdir -p "$TEST_TMP/x/pkg"
    printf '#!/bin/sh\n' > "$TEST_TMP/x/pkg/yazi"
    printf '#!/bin/sh\n' > "$TEST_TMP/x/pkg/ya"
    chmod +x "$TEST_TMP/x/pkg/yazi" "$TEST_TMP/x/pkg/ya"

    run _ghr_place_bins "$TEST_TMP/x" yazi ya
    [ "$status" -eq 0 ]
    [ -x "$ENVUP_LOCAL_BIN/yazi" ]
    [ -x "$ENVUP_LOCAL_BIN/ya" ]
}

@test "_ghr_place_bins: validates the archive before installing anything" {
    mkdir -p "$TEST_TMP/x/pkg"
    printf '#!/bin/sh\n' > "$TEST_TMP/x/pkg/yazi"
    chmod +x "$TEST_TMP/x/pkg/yazi"

    run _ghr_place_bins "$TEST_TMP/x" yazi ya
    [ "$status" -ne 0 ]
    [ ! -e "$ENVUP_LOCAL_BIN/yazi" ]
    [ ! -e "$ENVUP_LOCAL_BIN/ya" ]
}

# ---- github_release: installing a whole tree (GH_TREE) -------------------
#
# nvim ships as a prefix rather than a bare binary, so this path replaces a
# directory that is already in use. Both tests below are about the moment of
# replacement, which is the only moment an upgrade can leave you worse off than
# before you ran it.

# mk_release <dir> <bin>... — an extracted archive with a single top directory.
mk_release() {
    local d="$1"; shift
    VERIFY_BIN="$1"
    mkdir -p "$d/pkg/bin"
    local b
    for b in "$@"; do printf '#!/bin/sh\necho %s\n' "$b" > "$d/pkg/bin/$b"; chmod +x "$d/pkg/bin/$b"; done
}

@test "_ghr_place_tree: installs the tree and links its binaries" {
    mk_release "$TEST_TMP/x" nvim
    run _ghr_place_tree "$TEST_TMP/x"
    [ "$status" -eq 0 ]
    [ -x "$ENVUP_LOCAL_OPT/fixture/bin/nvim" ]
    [ -L "$ENVUP_LOCAL_BIN/nvim" ]
}

@test "_ghr_place_tree works under the install worker's nounset mode" {
    mk_release "$TEST_TMP/x" nvim
    run place_tree_nounset "$TEST_TMP/x"
    [ "$status" -eq 0 ]
    [ -x "$ENVUP_LOCAL_OPT/fixture/bin/nvim" ]
}

# It used to `rm -rf "$dest"` and only then mv. The mv crosses filesystems —
# temp dir to $HOME — which is exactly where mv does a real copy and can fail
# on space or permissions, and the old install was already gone by then.
@test "_ghr_place_tree: a failed install leaves the previous version in place" {
    mk_release "$TEST_TMP/x" nvim
    _ghr_place_tree "$TEST_TMP/x"
    echo "v1" > "$ENVUP_LOCAL_OPT/fixture/marker"

    mk_release "$TEST_TMP/y" nvim
    # Make the final swap-in fail, after the new tree has been staged.
    mv() { [[ "$2" == "$ENVUP_LOCAL_OPT/fixture" && "$1" == */new ]] && return 1; command mv "$@"; }
    run _ghr_place_tree "$TEST_TMP/y"
    unset -f mv

    [ "$status" -ne 0 ]
    [ -f "$ENVUP_LOCAL_OPT/fixture/marker" ]
    [ -x "$ENVUP_LOCAL_OPT/fixture/bin/nvim" ]
}

@test "_ghr_place_tree: no staging leftovers after a successful install" {
    mk_release "$TEST_TMP/x" nvim
    _ghr_place_tree "$TEST_TMP/x"
    run bash -c 'ls -d "$ENVUP_LOCAL_OPT"/fixture.* 2>/dev/null'
    [ -z "$output" ]
}

# `command -v` finds a dangling symlink, so envup would call the tool installed
# and the shell would report "not found" for a file that is right there.
@test "_ghr_place_tree: a binary the new release dropped stops being on PATH" {
    mk_release "$TEST_TMP/x" nvim nvim-qt
    _ghr_place_tree "$TEST_TMP/x"
    [ -L "$ENVUP_LOCAL_BIN/nvim-qt" ]

    mk_release "$TEST_TMP/y" nvim
    run _ghr_place_tree "$TEST_TMP/y"
    [ "$status" -eq 0 ]
    [ -L "$ENVUP_LOCAL_BIN/nvim" ]
    [ ! -e "$ENVUP_LOCAL_BIN/nvim-qt" ]
    [ ! -L "$ENVUP_LOCAL_BIN/nvim-qt" ]
}

@test "_ghr_place_tree: someone else's link into ~/.local/bin is left alone" {
    mkdir -p "$ENVUP_LOCAL_BIN"
    ln -s "/nowhere/at/all" "$ENVUP_LOCAL_BIN/unrelated"
    mk_release "$TEST_TMP/x" nvim
    run _ghr_place_tree "$TEST_TMP/x"
    [ "$status" -eq 0 ]
    [ -L "$ENVUP_LOCAL_BIN/unrelated" ]
}

@test "release candidates cannot use an old PATH tool to pass verification" {
    stub_bin fixture <<'EOF'
#!/bin/sh
echo fixture 9.0
EOF
    mkdir -p "$TEST_TMP/x"
    printf '#!/bin/sh\nexit 42\n' > "$TEST_TMP/x/fixture"
    mkdir -p "$ENVUP_LOCAL_BIN"
    ln -s "$STUB_BIN/fixture" "$ENVUP_LOCAL_BIN/fixture"
    run _ghr_place_bins "$TEST_TMP/x" fixture
    [ "$status" -ne 0 ]
    [ "$(readlink "$ENVUP_LOCAL_BIN/fixture")" = "$STUB_BIN/fixture" ]
    [ "$("$ENVUP_LOCAL_BIN/fixture")" = 'fixture 9.0' ]
}

@test "release candidates must meet the module version floor before replacement" {
    VERIFY_MIN_VERSION=2.0
    mkdir -p "$TEST_TMP/x" "$ENVUP_LOCAL_BIN"
    printf '#!/bin/sh\necho fixture 1.0\n' > "$TEST_TMP/x/fixture"
    printf '#!/bin/sh\necho fixture 0.5\n' > "$ENVUP_LOCAL_BIN/fixture"
    chmod +x "$ENVUP_LOCAL_BIN/fixture"
    run _ghr_place_bins "$TEST_TMP/x" fixture
    [ "$status" -ne 0 ]
    [ "$("$ENVUP_LOCAL_BIN/fixture")" = 'fixture 0.5' ]
}

@test "a mismatched locked candidate cannot overwrite the existing binary" {
    _ENG_TARGET_VERSION=2.0
    mkdir -p "$TEST_TMP/x" "$ENVUP_LOCAL_BIN"
    printf '#!/bin/sh\necho fixture 3.0\n' > "$TEST_TMP/x/fixture"
    printf '#!/bin/sh\necho fixture 1.0\n' > "$ENVUP_LOCAL_BIN/fixture"
    chmod +x "$ENVUP_LOCAL_BIN/fixture"
    run _ghr_place_bins "$TEST_TMP/x" fixture
    [ "$status" -eq 1 ]
    [ "$("$ENVUP_LOCAL_BIN/fixture")" = 'fixture 1.0' ]
}

@test "multi-binary activation restores all commands if a later move fails" {
    mkdir -p "$TEST_TMP/x" "$ENVUP_LOCAL_BIN"
    printf '#!/bin/sh\necho new\n' > "$TEST_TMP/x/yazi"
    cp "$TEST_TMP/x/yazi" "$TEST_TMP/x/ya"
    printf '#!/bin/sh\necho old\n' > "$ENVUP_LOCAL_BIN/yazi"
    chmod +x "$ENVUP_LOCAL_BIN/yazi"
    ln -s /private/ya "$ENVUP_LOCAL_BIN/ya"
    mv() { [[ "$1" == */new/ya ]] && return 1; command mv "$@"; }
    run _ghr_place_bins "$TEST_TMP/x" yazi ya
    [ "$status" -ne 0 ]
    [ "$("$ENVUP_LOCAL_BIN/yazi")" = old ]
    [ "$(readlink "$ENVUP_LOCAL_BIN/ya")" = /private/ya ]
    [[ "$output" == *'previous entries restored'* ]]
}

@test "release replacement preserves a symlink target instead of overwriting it" {
    mkdir -p "$TEST_TMP/x" "$ENVUP_LOCAL_BIN"
    printf '#!/bin/sh\necho private\n' > "$TEST_TMP/private"
    chmod +x "$TEST_TMP/private"
    ln -s "$TEST_TMP/private" "$ENVUP_LOCAL_BIN/fixture"
    printf '#!/bin/sh\necho new\n' > "$TEST_TMP/x/fixture"
    run _ghr_place_bins "$TEST_TMP/x" fixture
    [ "$status" -eq 0 ]
    [ ! -L "$ENVUP_LOCAL_BIN/fixture" ]
    [ "$("$ENVUP_LOCAL_BIN/fixture")" = new ]
    [ "$("$TEST_TMP/private")" = private ]
}

@test "tree candidate failure keeps the old runtime and command" {
    mk_release "$TEST_TMP/x" nvim
    _ghr_place_tree "$TEST_TMP/x"
    echo old > "$ENVUP_LOCAL_OPT/fixture/marker"
    mk_release "$TEST_TMP/y" nvim
    printf '#!/bin/sh\nexit 42\n' > "$TEST_TMP/y/pkg/bin/nvim"
    run _ghr_place_tree "$TEST_TMP/y"
    [ "$status" -ne 0 ]
    [ "$(cat "$ENVUP_LOCAL_OPT/fixture/marker")" = old ]
    [ "$("$ENVUP_LOCAL_BIN/nvim")" = nvim ]
}

@test "tree link activation failure restores runtime and private command links" {
    mk_release "$TEST_TMP/x" nvim
    _ghr_place_tree "$TEST_TMP/x"
    echo old > "$ENVUP_LOCAL_OPT/fixture/marker"
    ln -s /private/qt "$ENVUP_LOCAL_BIN/nvim-qt"
    mk_release "$TEST_TMP/y" nvim nvim-qt
    mv() { [[ "$1" == *.envup.*/nvim-qt ]] && return 1; command mv "$@"; }
    run _ghr_place_tree "$TEST_TMP/y"
    [ "$status" -ne 0 ]
    [ "$(cat "$ENVUP_LOCAL_OPT/fixture/marker")" = old ]
    [ "$("$ENVUP_LOCAL_BIN/nvim")" = nvim ]
    [ "$(readlink "$ENVUP_LOCAL_BIN/nvim-qt")" = /private/qt ]
}

@test "final-path verification failure restores a previously absent binary" {
    mkdir -p "$TEST_TMP/x"
    printf '#!/bin/sh\ncase "$0" in */new/*) echo ready;; *) exit 42;; esac\n' > "$TEST_TMP/x/fixture"
    run _ghr_place_bins "$TEST_TMP/x" fixture
    [ "$status" -ne 0 ]
    [ ! -e "$ENVUP_LOCAL_BIN/fixture" ]
    [[ "$output" == *'previous entries restored'* ]]
}

@test "failed recovery retains the old binary and reports its backup path" {
    mkdir -p "$TEST_TMP/x" "$ENVUP_LOCAL_BIN"
    printf '#!/bin/sh\necho old\n' > "$ENVUP_LOCAL_BIN/fixture"
    printf '#!/bin/sh\necho new\n' > "$TEST_TMP/x/fixture"
    mv() { [[ "$1" == */new/fixture || "$1" == */old/0 ]] && return 1; command mv "$@"; }
    run _ghr_place_bins "$TEST_TMP/x" fixture
    [ "$status" -ne 0 ]
    [[ "$output" == *'could not restore'*'backup retained in'* ]]
    [[ "$output" != *'previous entries restored'* ]]
    local backup
    backup="$(find "$ENVUP_LOCAL_BIN" -path '*/old/0' -type f)"
    [ -n "$backup" ]
    [ "$(cat "$backup")" = $'#!/bin/sh\necho old' ]
}

@test "termination immediately after backup restores the original command" {
    mkdir -p "$TEST_TMP/x" "$ENVUP_LOCAL_BIN"
    printf '#!/bin/sh\necho old\n' > "$ENVUP_LOCAL_BIN/fixture"
    chmod +x "$ENVUP_LOCAL_BIN/fixture"
    printf '#!/bin/sh\necho new\n' > "$TEST_TMP/x/fixture"
    mv() {
        command mv "$@" || return
        [[ "$2" != */old/0 ]] || kill -TERM "$BASHPID"
    }
    run _ghr_place_bins "$TEST_TMP/x" fixture
    [ "$status" -eq 143 ]
    [ "$("$ENVUP_LOCAL_BIN/fixture")" = old ]
    [[ "$output" == *'previous entries restored'* ]]
}

@test "tree failing at its final path restores the runtime and obsolete links" {
    mk_release "$TEST_TMP/x" nvim nvim-qt
    _ghr_place_tree "$TEST_TMP/x"
    echo old > "$ENVUP_LOCAL_OPT/fixture/marker"
    mk_release "$TEST_TMP/y" nvim
    printf '#!/bin/sh\ncase "$0" in */new/bin/*) echo ready;; *) exit 42;; esac\n' > "$TEST_TMP/y/pkg/bin/nvim"
    run _ghr_place_tree "$TEST_TMP/y"
    [ "$status" -ne 0 ]
    [ "$(cat "$ENVUP_LOCAL_OPT/fixture/marker")" = old ]
    [ "$("$ENVUP_LOCAL_BIN/nvim")" = nvim ]
    [ "$("$ENVUP_LOCAL_BIN/nvim-qt")" = nvim-qt ]
}

@test "tree missing its primary executable cannot replace the old runtime" {
    mk_release "$TEST_TMP/x" nvim
    _ghr_place_tree "$TEST_TMP/x"
    echo old > "$ENVUP_LOCAL_OPT/fixture/marker"
    mk_release "$TEST_TMP/y" other
    VERIFY_BIN=nvim
    run _ghr_place_tree "$TEST_TMP/y"
    [ "$status" -ne 0 ]
    [ "$(cat "$ENVUP_LOCAL_OPT/fixture/marker")" = old ]
    [ "$("$ENVUP_LOCAL_BIN/nvim")" = nvim ]
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
