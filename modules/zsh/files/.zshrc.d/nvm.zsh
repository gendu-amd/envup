# ============================================
# NVM (Node Version Manager)
# ============================================
# Load nvm if installed

export NVM_DIR="${HOME}/.nvm"

# Load nvm (nvm.sh may reference unset variables, so we disable strict mode)
if [[ -s "${NVM_DIR}/nvm.sh" ]]; then
    \. "${NVM_DIR}/nvm.sh" 2>/dev/null || true
fi

# Load nvm bash_completion
if [[ -s "${NVM_DIR}/bash_completion" ]]; then
    \. "${NVM_DIR}/bash_completion" 2>/dev/null || true
fi

# npm's global prefix, when configured away from the (root-owned) default via
# `npm config set prefix ~/.npm-global`. Conditional on the dir existing, so
# machines that never set it are unaffected.
if [[ -d "${HOME}/.npm-global/bin" ]] && [[ ":${PATH}:" != *":${HOME}/.npm-global/bin:"* ]]; then
    export PATH="${HOME}/.npm-global/bin:${PATH}"
fi
