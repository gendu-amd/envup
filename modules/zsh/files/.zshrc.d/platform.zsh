# ============================================
# Platform Detection and Configuration
# ============================================

# ---------------------------
# Detect Platform
# ---------------------------
# Canonical rule (see docs/ARCHITECTURE.md "Platform detection"). Must stay
# identical to the install-time detector in lib.sh so the runtime (zsh) and
# install-time (bash) verdicts never drift.
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
        *) echo "linux" ;;  # Fallback to linux for unknown Unix-like systems
    esac
}

# Export platform variables
export ENVUP_PLATFORM=$(_detect_platform)
export ENVUP_ARCH=$(uname -m)

# ---------------------------
# Load Platform-Specific Config
# ---------------------------
_platform_config="${HOME}/.zshrc.d/platform/${ENVUP_PLATFORM}.zsh"
[[ -f "$_platform_config" ]] && source "$_platform_config"

# Cleanup
unfunction _detect_platform 2>/dev/null
unset _platform_config
