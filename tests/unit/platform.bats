#!/usr/bin/env bats
# N-1: the install-time (lib/caps.sh) and runtime (20-platform.zsh) platform
# detectors must not drift. lib/caps.sh's verdict is checked against an
# independent copy of the canonical rule, 20-platform.zsh is checked to use the
# same discriminators, and a third copy appearing anywhere fails the suite —
# there used to be one in env.zsh, and it had already drifted.

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

@test "20-platform.zsh uses the same discriminators as lib/caps.sh" {
    local pz="$REPO_ROOT/modules/zsh/files/.zshrc.d/20-platform.zsh"
    grep -q 'microsoft' "$pz"
    grep -q '/\.dockerenv' "$pz"
    grep -q 'containerd' "$pz"
}

@test "there are exactly two container detectors: bash and zsh" {
    # env.zsh had a third. It ran before the platform slice, used only
    # /proc/1/cgroup, and set WORKSPACE from a verdict the rest of the config
    # disagreed with. Any new copy is a future drift bug; reuse ENVUP_PLATFORM.
    local -a hits
    mapfile -t hits < <(
        cd "$REPO_ROOT" &&
        grep -rl '/\.dockerenv' \
            lib envup lib.sh modules/*/meta.sh modules/*/hooks.sh \
            modules/zsh/files 2>/dev/null | sort
    )
    printf 'found: %s\n' "${hits[*]}"
    [ "${#hits[@]}" -eq 2 ]
    [[ "${hits[*]}" == *"lib/caps.sh"* ]]
    [[ "${hits[*]}" == *"20-platform.zsh"* ]]
}

@test "20-platform.zsh normalises arch the same way lib/caps.sh does" {
    # uname -m says arm64 on macOS and aarch64 on Linux for the same chip.
    # The zsh side exported the raw string, so ENVUP_ARCH meant one thing at
    # install time and another in the shell.
    local pz="$REPO_ROOT/modules/zsh/files/.zshrc.d/20-platform.zsh"
    grep -q 'aarch64|arm64' "$pz"
    grep -q 'x86_64|amd64' "$pz"
}
