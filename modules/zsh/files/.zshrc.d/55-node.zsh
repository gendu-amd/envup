# ============================================
# 55 — node / nvm, lazily
# ============================================
# Sourcing nvm.sh at startup costs 200-800ms — it is a 3500-line shell script
# and it walks $NVM_DIR. Most shells never run a node command at all, so the
# cost was pure waste on every prompt.
#
# Instead: shims. The first call to nvm/node/npm/npx/yarn/pnpm removes all the
# shims, sources nvm for real, and re-runs what you typed. From then on the
# real commands are in place and there is no further overhead.

export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"

# npm's global prefix, when moved off the root-owned default with
# `npm config set prefix ~/.npm-global`.
path_prepend "$HOME/.npm-global/bin"

if [[ -s "$NVM_DIR/nvm.sh" ]]; then
    _nvm_load() {
        unfunction nvm node npm npx yarn pnpm 2>/dev/null
        source "$NVM_DIR/nvm.sh"
        [[ -s "$NVM_DIR/bash_completion" ]] && source "$NVM_DIR/bash_completion"
    }
    () {
        local c
        for c in nvm node npm npx yarn pnpm; do
            # A real binary already on PATH (a system node, or one nvm already
            # activated in a parent shell) is left alone — shimming it would
            # make the shim permanent.
            (( $+commands[$c] )) && [[ "$c" != nvm ]] && continue
            eval "$c() { _nvm_load; command -v $c >/dev/null && $c \"\$@\" }"
        done
    }
fi
