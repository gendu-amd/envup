# ============================================
# 20 — platform detection
# ============================================
# Runs BEFORE tools and aliases. On macOS this slice is what executes
# `brew shellenv`; when it ran last (it used to), zoxide/atuin/fzf were not yet
# on PATH when their init lines looked for them, so all three silently did
# nothing on every Mac. Anything that puts a toolchain on PATH belongs here.
#
# The detection rule is canonical — docs/ARCHITECTURE.md, "Platform detection" —
# and must stay identical to the install-time detector in lib/caps.sh. There are
# exactly two implementations, one per language, and tests/unit/platform.bats
# fails if a third appears.

_detect_platform() {
    case "$(uname -s)" in
        Darwin) echo "macos" ;;
        Linux)
            if [[ -r /proc/version ]] && grep -qi microsoft /proc/version 2>/dev/null; then
                echo "wsl2"
            elif [[ -f /.dockerenv ]] || grep -q 'docker\|containerd' /proc/1/cgroup 2>/dev/null; then
                echo "docker"
            else
                echo "linux"
            fi
            ;;
        *) echo "linux" ;;
    esac
}

export ENVUP_PLATFORM="$(_detect_platform)"

# Normalised, matching lib/caps.sh: uname says arm64 on macOS and aarch64 on
# Linux for the same silicon, and code that branches on the raw string gets one
# of the two wrong.
case "$(uname -m)" in
    x86_64|amd64)   export ENVUP_ARCH=x86_64 ;;
    aarch64|arm64)  export ENVUP_ARCH=aarch64 ;;
    armv7l|armv7)   export ENVUP_ARCH=armv7 ;;
    i386|i686)      export ENVUP_ARCH=i686 ;;
    *)              export ENVUP_ARCH="$(uname -m)" ;;
esac

# Short hostname — the key for the hosts/ layer in slice 70.
export ENVUP_HOST="${ENVUP_HOST:-${$(hostname -s 2>/dev/null || hostname 2>/dev/null):-unknown}}"

_platform_config="${HOME}/.zshrc.d/platform/${ENVUP_PLATFORM}.zsh"
[[ -f "$_platform_config" ]] && source "$_platform_config"

unfunction _detect_platform 2>/dev/null
unset _platform_config
