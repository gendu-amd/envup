#!/usr/bin/env bats
# Portable command helpers and the profile boundary that keeps TUIs optional.

load '../test_helper'

setup() {
    common_setup
    NAME=""; VERIFY_BIN=""; GH_BIN=""; GH_BINS=(); PKG_NAMES=(); PKG_DEFAULT=""
}
teardown() { common_teardown; }

load_module() {
    source "$REPO_ROOT/modules/$1/meta.sh"
    [[ -f "$REPO_ROOT/modules/$1/hooks.sh" ]] && source "$REPO_ROOT/modules/$1/hooks.sh"
    return 0
}
pick() { printf '%s\n' "$@" | _ghr_pick; }

@test "lazygit uses a release where distro packages are unavailable" {
    load_module lazygit
    [ "$(ENVUP_PKG=apt pkg_name)" = - ]
    ENVUP_OS=linux ENVUP_ARCH=x86_64 ENVUP_LIBC=glibc-2.35
    run pick \
        https://github.com/jesseduffield/lazygit/releases/download/v0.65.0/lazygit_0.65.0_linux_arm64.tar.gz \
        https://github.com/jesseduffield/lazygit/releases/download/v0.65.0/lazygit_0.65.0_linux_x86_64.tar.gz
    [[ "$output" == *linux_x86_64.tar.gz ]]
}

@test "yazi installs both commands and prefers the portable musl build" {
    load_module yazi
    [ "${GH_BINS[*]}" = "yazi ya" ]
    ENVUP_OS=linux ENVUP_ARCH=x86_64 ENVUP_LIBC=glibc-2.28
    run pick \
        https://github.com/sxyazi/yazi/releases/download/v26.9.1/yazi-x86_64-unknown-linux-gnu.zip \
        https://github.com/sxyazi/yazi/releases/download/v26.9.1/yazi-x86_64-unknown-linux-musl.zip
    [[ "$output" == *linux-musl.zip ]]
}

@test "yazi is incomplete when its companion command is missing" {
    load_module yazi
    isolate_path
    stub_bin yazi <<'EOF'
#!/bin/sh
echo 'Yazi 26.9.1'
EOF
    run verify
    [ "$status" -ne 0 ]

    stub_bin ya <<'EOF'
#!/bin/sh
echo 'Ya 26.9.1'
EOF
    run verify
    [ "$status" -eq 0 ]
}

@test "jq picks the executable, not its source archive" {
    load_module jq
    ENVUP_OS=linux ENVUP_ARCH=x86_64 ENVUP_LIBC=glibc-2.35
    run pick \
        https://github.com/jqlang/jq/releases/download/jq-1.8.2/jq-1.8.2.tar.gz \
        https://github.com/jqlang/jq/releases/download/jq-1.8.2/jq-linux-amd64
    [[ "$output" == */jq-linux-amd64 ]]
}

@test "tealdeer installs its release as the tldr command" {
    load_module tealdeer
    [ "$VERIFY_BIN" = tldr ]
    ENVUP_OS=macos ENVUP_ARCH=aarch64 ENVUP_LIBC=""
    run pick \
        https://github.com/tealdeer-rs/tealdeer/releases/download/v1.9.0/tealdeer-linux-x86_64-musl \
        https://github.com/tealdeer-rs/tealdeer/releases/download/v1.9.0/tealdeer-macos-aarch64
    [[ "$output" == *tealdeer-macos-aarch64 ]]
}

@test "the default profile keeps interactive TUIs optional" {
    local sandbox_home="$ENVUP_HOME"
    ENVUP_HOME="$REPO_ROOT"
    MODULES=(); load_profile standard
    [[ " ${MODULES[*]} " == *" jq "* ]]
    [[ " ${MODULES[*]} " == *" tealdeer "* ]]
    [[ " ${MODULES[*]} " != *" lazygit "* ]]
    [[ " ${MODULES[*]} " != *" yazi "* ]]

    MODULES=(); load_profile full
    [[ " ${MODULES[*]} " == *" lazygit "* ]]
    [[ " ${MODULES[*]} " == *" yazi "* ]]
    ENVUP_HOME="$sandbox_home"
}
