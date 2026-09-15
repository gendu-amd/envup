# Setup fzf
# ---------
if [[ -d "$HOME/.fzf/bin" ]] && [[ ! "$PATH" == *"$HOME/.fzf/bin"* ]]; then
  PATH="${PATH:+${PATH}:}$HOME/.fzf/bin"
fi

# Load fzf keybindings and completion
if command -v fzf &>/dev/null; then
  source <(fzf --zsh 2>/dev/null) || true
fi
