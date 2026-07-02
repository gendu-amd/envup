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
