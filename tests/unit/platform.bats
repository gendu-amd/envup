#!/usr/bin/env bats
# N-1: the install-time (lib.sh) and runtime (platform.zsh) platform detectors
# must not drift. lib.sh's verdict is checked against an independent copy of the
# canonical rule, and platform.zsh is checked to use the same discriminators.

load '../test_helper'

setup() { common_setup; }
teardown() { common_teardown; }

# Independent reimplementation of the canonical rule (docs/ARCHITECTURE.md).
_canon() {
    case "$(uname -s)" in
        Darwin) echo macos ;;
        Linux)
            if grep -qi microsoft /proc/version 2>/dev/null; then echo wsl2
            elif [[ -f /.dockerenv ]] || grep -q 'docker\|containerd' /proc/1/cgroup 2>/dev/null; then echo docker
            else echo linux; fi ;;
        *) echo linux ;;
    esac
}

@test "lib.sh ENVUP_PLATFORM matches the canonical rule" {
    [ "$ENVUP_PLATFORM" = "$(_canon)" ]
}

@test "ENVUP_PLATFORM is one of the canonical values" {
    case "$ENVUP_PLATFORM" in
        macos|wsl2|docker|linux) : ;;
        *) echo "unexpected: $ENVUP_PLATFORM"; false ;;
    esac
}

@test "platform.zsh uses the same discriminators as lib.sh" {
    local pz="$REPO_ROOT/modules/zsh/files/.zshrc.d/platform.zsh"
    grep -q 'microsoft' "$pz"
    grep -q '/\.dockerenv' "$pz"
    grep -q 'containerd' "$pz"
}
