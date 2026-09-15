# ============================================
# macOS
# ============================================
# The most important two lines in the whole config are the brew ones: without
# `brew shellenv` nothing installed by brew is on PATH, and this slice now runs
# before the tool and alias slices that depend on it.
#
# Note what is NOT here any more: `alias ls="ls -G"`. It lived here, this slice
# used to load last, and so it silently overwrote the eza alias — a Mac with
# eza installed still got plain BSD ls. Colour handling now lives with every
# other ls decision, in slice 60.

if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
fi

# GNU coreutils, when installed, without the g- prefix.
path_prepend "${HOMEBREW_PREFIX:-/opt/homebrew}/opt/coreutils/libexec/gnubin"

alias flush-dns="sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder"
alias showfiles="defaults write com.apple.finder AppleShowAllFiles YES && killall Finder"
alias hidefiles="defaults write com.apple.finder AppleShowAllFiles NO && killall Finder"

alias o="open ."
alias finder="open -a Finder"
alias ql="qlmanage -p"
alias update="softwareupdate -ia"
alias cleanup="find . -type f -name '*.DS_Store' -delete"
