# ============================================
# 80 — personal overrides, never committed
# ============================================
# Loads last, so it wins over everything.
#
# These live in $HOME rather than inside the repo checkout. A gitignored file
# inside the checkout is a trap: `envup upgrade` runs `git pull`, tools append
# to files they find in $HOME, and anything writing to ~/.zshrc was writing into
# version control. Nothing in $HOME/.zshrc.local can dirty the repo.
#
#   ~/.zshrc.local              personal, all machines that share this home
#   ~/.zshrc.local.<hostname>   personal, this machine only
#
# For machine config you want to keep and sync, use hosts/ in slice 70 instead.

[[ -r "$HOME/.zshrc.local" ]]                && source "$HOME/.zshrc.local"
[[ -r "$HOME/.zshrc.local.${ENVUP_HOST}" ]]  && source "$HOME/.zshrc.local.${ENVUP_HOST}"

# The pre-0.2 location. Sourced so nobody silently loses their settings, with a
# one-line nudge to move it somewhere that cannot end up in a commit.
if [[ -r "$HOME/.zshrc.d/local.zsh" ]]; then
    source "$HOME/.zshrc.d/local.zsh"
    print -u2 "[envup] ~/.zshrc.d/local.zsh is inside the repo checkout — move it to ~/.zshrc.local"
fi
