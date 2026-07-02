# ============================================
# Docker Container Specific Configuration
# ============================================

# Skip in non-interactive mode
[[ ! -t 0 ]] && return

# Inherit Linux config (ROCm/CUDA paths, system aliases)
[[ -f "${0:A:h}/linux.zsh" ]] && source "${0:A:h}/linux.zsh"

# Note: TERM fix is in .zshenv (must be early for p10k)

# Disable features that don't work in containers
unset BROWSER

# Mount detection - auto-detect workspace
for _ws_path in "/workspace" "/mnt/workspace" "/mnt/host"; do
    if [[ -d "$_ws_path" ]]; then
        export WORKSPACE="$_ws_path"
        alias ws="cd $WORKSPACE"
        break
    fi
done
unset _ws_path
