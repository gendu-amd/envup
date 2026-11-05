# ============================================
# WSL2
# ============================================
[[ -f "${0:A:h}/linux.zsh" ]] && source "${0:A:h}/linux.zsh"

# Exported, not a local: the win* functions below read it when they are
# called, which is long after this file has finished.
export WIN_DRIVE="/mnt/c"
[[ -d /mnt/d/Windows && ! -d /mnt/c/Windows ]] && WIN_DRIVE="/mnt/d"

export BROWSER="${WIN_DRIVE}/Windows/System32/cmd.exe /c start"
export DONT_PROMPT_WSL_INSTALL=1

alias clip="clip.exe"
alias pbcopy="clip.exe"
alias pbpaste="powershell.exe -command 'Get-Clipboard' | tr -d '\r'"
alias explorer="explorer.exe"
alias open="explorer.exe"
alias wslopen="cmd.exe /c start"

# win_user — the Windows account name, cached.
#
# This used to call cmd.exe twice on every shell start: 200-500ms each, both on
# the critical path to the prompt, to answer a question whose answer never
# changes. Now it is read once and written to the cache; delete the file if you
# ever need it re-detected.
win_user() {
    local cache="${XDG_CACHE_HOME:-$HOME/.cache}/envup/win_user"
    if [[ -s "$cache" ]]; then
        cat "$cache"
        return 0
    fi
    local u
    u="$(cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\r\n')"
    [[ -n "$u" ]] || return 1
    mkdir -p "${cache:h}" && print -r -- "$u" > "$cache"
    print -r -- "$u"
}

# Resolved lazily for the same reason: WIN_HOME is only interesting if you
# actually reach for it, and a startup that shells out to Windows is a startup
# you feel.
winhome() { cd "${WIN_DRIVE}/Users/$(win_user)" }
windesk() { cd "${WIN_DRIVE}/Users/$(win_user)/Desktop" }
windl()   { cd "${WIN_DRIVE}/Users/$(win_user)/Downloads" }
