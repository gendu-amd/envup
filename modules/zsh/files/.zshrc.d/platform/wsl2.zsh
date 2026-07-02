# ============================================
# WSL2 Specific Configuration
# ============================================

# Inherit Linux config first
[[ -f "${0:A:h}/linux.zsh" ]] && source "${0:A:h}/linux.zsh"

# Windows integration
# Detect Windows system drive dynamically (usually /mnt/c, but configurable)
_win_drive="/mnt/c"
if [[ -d "/mnt/c/Windows" ]]; then
    _win_drive="/mnt/c"
elif [[ -d "/mnt/d/Windows" ]]; then
    _win_drive="/mnt/d"
fi

export BROWSER="${_win_drive}/Windows/System32/cmd.exe /c start"

# Windows clipboard integration
alias clip="clip.exe"
alias pbcopy="clip.exe"
alias pbpaste="powershell.exe -command 'Get-Clipboard' | tr -d '\r'"

# Open Windows Explorer
alias explorer="explorer.exe"
alias open="explorer.exe"

# Open with default Windows application
alias wslopen="cmd.exe /c start"

# Get Windows username
win_user() {
    cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\r'
}

# Windows home directory
export WIN_HOME="${_win_drive}/Users/$(win_user 2>/dev/null)"

# Quick access to Windows directories (only if paths exist)
[[ -d "$WIN_HOME" ]] && alias winhome="cd $WIN_HOME"
[[ -d "$WIN_HOME/Desktop" ]] && alias windesk="cd $WIN_HOME/Desktop"
[[ -d "$WIN_HOME/Downloads" ]] && alias windl="cd $WIN_HOME/Downloads"

unset _win_drive

# VS Code integration (if installed)
if command -v code &>/dev/null; then
    alias code="code"
elif [[ -x "/mnt/c/Users/$(win_user)/AppData/Local/Programs/Microsoft VS Code/bin/code" ]]; then
    alias code="/mnt/c/Users/$(win_user)/AppData/Local/Programs/Microsoft\ VS\ Code/bin/code"
fi

# Docker Desktop integration (if using Docker Desktop)
# WSL2 backend is automatically configured

# Fix interop issues
export DONT_PROMPT_WSL_INSTALL=1

