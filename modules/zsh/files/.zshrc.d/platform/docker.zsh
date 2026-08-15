# ============================================
# Container
# ============================================
# Inherits the Linux config; WORKSPACE detection lives in slice 30 (there used
# to be three independent copies of "am I in a container", which drifted).

[[ -f "${0:A:h}/linux.zsh" ]] && source "${0:A:h}/linux.zsh"

# Nothing here can open a browser.
unset BROWSER
