# ============================================
# 70 — per-machine config, committed
# ============================================
# The only per-machine layer used to be local.zsh, which is gitignored — so
# every machine-specific setting (a proxy, a CUDA prefix, a `module load`, the
# timezone) existed on exactly one machine and was lost the moment that machine
# was rebuilt. Worse, local.zsh lives inside the repo checkout, so on a home
# directory shared over NFS all the machines shared the same "per-machine" file.
#
# hosts/<short-hostname>.zsh is committed. It syncs, it survives a rebuild, and
# because the filename is the hostname it stays separate on a shared home.
#
#   cp ~/.zshrc.d/hosts/example.zsh.template ~/.zshrc.d/hosts/$(hostname -s).zsh
#
# Truly private things (tokens, one-off experiments) still belong in slice 80.

[[ -r "$HOME/.zshrc.d/hosts/${ENVUP_HOST}.zsh" ]] && source "$HOME/.zshrc.d/hosts/${ENVUP_HOST}.zsh"
