# ============================================
# Environment Variables
# ============================================

# Workspace detection (mainly for Docker/container environments)
if [[ -f /.dockerenv ]] || grep -q 'docker\|containerd' /proc/1/cgroup 2>/dev/null; then
    # Container: auto-detect workspace mount point
    for _try_path in "/workspace" "/mnt/workspace" "/mnt/host"; do
        [[ -d "${_try_path}" ]] && export WORKSPACE="${_try_path}" && break
    done
    export WORKSPACE="${WORKSPACE:-/workspace}"
fi

# ---------------------------
# Basic Environment
# ---------------------------
# Timezone: override in local.zsh if needed
export TZ="${TZ:-UTC}"
export EDITOR="nvim"
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# ---------------------------
# PATH
# ---------------------------
export PATH="${HOME}/.local/bin:${PATH}"

# Cleanup
unset _try_path
