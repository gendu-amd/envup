#!/bin/bash
# git hooks: carry the machine's existing identity across, and make sure the
# per-machine include target exists.

pre_install() {
    # Read the identity BEFORE the link replaces ~/.gitconfig — afterwards the
    # old file is in the backup dir and this answer is gone.
    _GIT_CARRY_NAME="$(git config --global user.name  2>/dev/null || true)"
    _GIT_CARRY_MAIL="$(git config --global user.email 2>/dev/null || true)"
    return 0
}

post_install() {
    local cfg="$HOME/.gitconfig.local"
    if [[ "${ENVUP_DRY_RUN:-0}" == 1 ]]; then
        log_info "[dry-run] would ensure $cfg exists"; return 0
    fi
    [[ -e "$cfg" ]] && return 0

    cat > "$cfg" <<EOF
# Per-machine git identity — NOT in the repo. Loaded last via [include].
[user]
    name  = ${_GIT_CARRY_NAME:-YOUR NAME}
    email = ${_GIT_CARRY_MAIL:-your.email@example.com}
EOF
    if [[ -n "$_GIT_CARRY_NAME" && -n "$_GIT_CARRY_MAIL" ]]; then
        log_success "created $cfg (kept the identity this machine already had)"
    else
        log_warn "created $cfg — set a real name/email or 'git commit' will refuse to run"
        log_hint "edit it: \$EDITOR $cfg"
    fi
}

post_uninstall() {
    # shellcheck disable=SC2088  # literal ~ is display text, not a path to expand
    log_info "~/.gitconfig.local (your identity) kept"
    return 0
}
