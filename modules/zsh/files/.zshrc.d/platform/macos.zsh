# ============================================
# macOS Specific Configuration
# ============================================

# Homebrew setup (Apple Silicon vs Intel)
if [[ -x "/opt/homebrew/bin/brew" ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -x "/usr/local/bin/brew" ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
fi

# macOS-specific aliases
alias ls="ls -G"                    # Colored ls
alias flush-dns="sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder"
alias showfiles="defaults write com.apple.finder AppleShowAllFiles YES && killall Finder"
alias hidefiles="defaults write com.apple.finder AppleShowAllFiles NO && killall Finder"

# Clipboard (native)
# pbcopy and pbpaste are already available

# Open in Finder
alias o="open ."
alias finder="open -a Finder"

# Quick Look
alias ql="qlmanage -p"

# macOS system commands
alias update="softwareupdate -ia"
alias cleanup="find . -type f -name '*.DS_Store' -delete"

# Disable Gatekeeper temporarily (use with caution)
alias gatekeeper-off="sudo spctl --master-disable"
alias gatekeeper-on="sudo spctl --master-enable"

