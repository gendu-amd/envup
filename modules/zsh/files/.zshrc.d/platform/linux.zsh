# ============================================
# Linux Specific Configuration
# ============================================

# Clipboard (macOS-style aliases)
if command -v xclip &>/dev/null; then
    alias pbcopy="xclip -selection clipboard"
    alias pbpaste="xclip -selection clipboard -o"
elif command -v xsel &>/dev/null; then
    alias pbcopy="xsel --clipboard --input"
    alias pbpaste="xsel --clipboard --output"
fi

# System info
alias meminfo="free -h"
alias cpuinfo="lscpu"

# ROCm environment (AMD GPU)
if [[ -d "/opt/rocm" ]]; then
    export ROCM_PATH=/opt/rocm
    export PATH=${PATH}:${ROCM_PATH}/bin
    export LD_LIBRARY_PATH=${LD_LIBRARY_PATH:-}:${ROCM_PATH}/lib
    # ROCm profiler shortcut
    alias rprof="rocprof --stats"
fi

# CUDA environment (NVIDIA GPU)
if [[ -d "/usr/local/cuda" ]]; then
    export CUDA_HOME=/usr/local/cuda
    export PATH=${PATH}:${CUDA_HOME}/bin
    export LD_LIBRARY_PATH=${LD_LIBRARY_PATH:-}:${CUDA_HOME}/lib64
fi
