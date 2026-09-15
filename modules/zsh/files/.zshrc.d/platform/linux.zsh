# ============================================
# Linux
# ============================================
# Loaded from slice 20, so anything put on PATH here is visible to the tool and
# alias slices that follow.

if (( $+commands[xclip] )); then
    alias pbcopy="xclip -selection clipboard"
    alias pbpaste="xclip -selection clipboard -o"
elif (( $+commands[xsel] )); then
    alias pbcopy="xsel --clipboard --input"
    alias pbpaste="xsel --clipboard --output"
fi

alias meminfo="free -h"
alias cpuinfo="lscpu"

# GPU toolchains. Appended through the slice-10 helpers: the old
# `export PATH=$PATH:$ROCM_PATH/bin` re-appended in every nested shell, so a
# tmux pane inside an ssh session inside a container carried the same entry
# three times over.
if [[ -d /opt/rocm ]]; then
    export ROCM_PATH=/opt/rocm
    path_append "$ROCM_PATH/bin"
    envvar_path_append LD_LIBRARY_PATH "$ROCM_PATH/lib"
    alias rprof="rocprof --stats"
fi

if [[ -d /usr/local/cuda ]]; then
    export CUDA_HOME=/usr/local/cuda
    path_append "$CUDA_HOME/bin"
    envvar_path_append LD_LIBRARY_PATH "$CUDA_HOME/lib64"
fi
