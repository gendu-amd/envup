#!/bin/bash
# git install hook: install git, symlink the shared .gitconfig, and make sure
# ~/.gitconfig.local exists for your per-machine identity.
#
# The shared .gitconfig has NO [user] section (identity is personal) and ends
# with `[include] ~/.gitconfig.local`, so your name/email stay out of the repo.

_git_install() {
    pkg_have git || pkg_install git || return 1

    # Capture any identity already set on this machine BEFORE we replace
    # ~/.gitconfig, so we can carry it over instead of clobbering it.
    local name email
    name=$(git config --global user.name 2>/dev/null || true)
    email=$(git config --global user.email 2>/dev/null || true)

    safe_link "modules/git/files/.gitconfig" "$HOME/.gitconfig" || return 1

    local local_cfg="$HOME/.gitconfig.local"
    [[ "${ENVUP_DRY_RUN:-0}" == 1 ]] && { log_info "[dry-run] would ensure $local_cfg exists"; return 0; }
    [[ -e "$local_cfg" ]] && return 0

    cat > "$local_cfg" <<EOF
# Per-machine git identity — NOT in the repo. Loaded last via [include].
[user]
    name  = ${name:-YOUR NAME}
    email = ${email:-your.email@example.com}
EOF
    if [[ -n "$name" && -n "$email" ]]; then
        log_success "created $local_cfg (kept your existing identity)"
    else
        log_warn "created $local_cfg — set a real name/email or 'git commit' will fail"
        log_hint "edit it: \$EDITOR $local_cfg"
    fi
}
_git_install
