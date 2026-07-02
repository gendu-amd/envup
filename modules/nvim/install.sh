#!/bin/bash
# nvim install hook: install neovim, symlink the NvChad config to ~/.config/nvim,
# and install plugins via lazy.nvim.
#
# NvChad needs nvim >= 0.10. If the distro ships something older we print
# upgrade options and stop — envup never touches your system package sources.
#
# Plugins are pinned by the committed lazy-lock.json and restored from it, so a
# nvim 0.10 host and a nvim 0.11 container end up with the identical plugin set
# (the pins in lua/plugins/init.lua are chosen to work on both). Override with
# ENVUP_NVIM_LAZY: restore (default) / sync (bump+rewrite lock) / skip.

NVIM_MIN="0.10"

_nvim_recent_enough() {
    have nvim || return 1
    local v
    v=$(nvim --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1)
    [[ -n "$v" ]] && [[ "$(printf '%s\n%s\n' "$NVIM_MIN" "$v" | sort -V | head -1)" == "$NVIM_MIN" ]]
}

_nvim_bootstrap_lazy() {
    local data="${XDG_DATA_HOME:-$HOME/.local/share}/nvim"
    local lazy="$data/lazy/lazy.nvim"

    [[ -f "$lazy/lua/lazy/init.lua" ]] && return 0
    [[ "${ENVUP_DRY_RUN:-0}" == 1 ]] && { log_info "[dry-run] would bootstrap lazy.nvim at $lazy"; return 0; }
    pkg_have git || { log_error "nvim plugins need git on PATH"; return 1; }

    # File or broken symlink here blocks mkdir (WSL "File exists" on fresh install).
    [[ -d "$data" ]] || rm -f "$data"
    mkdir -p "$(dirname "$lazy")"
    [[ -d "$lazy" ]] && rm -rf "$lazy"

    log_step "Bootstrapping lazy.nvim"
    net_run "lazy.nvim bootstrap" -- git clone --filter=blob:none \
        "$(gh_url https://github.com/folke/lazy.nvim.git)" --branch=stable "$lazy" \
        || { log_error "git clone lazy.nvim failed"; return 1; }
    [[ -f "$lazy/lua/lazy/init.lua" ]] || { log_error "lazy.nvim missing after clone"; return 1; }
    log_success "lazy.nvim bootstrapped"
}

_nvim_install() {
    have nvim || pkg_install neovim || return 1

    if ! _nvim_recent_enough; then
        log_error "nvim too old: $(nvim --version 2>/dev/null | head -1) — NvChad needs >= $NVIM_MIN"
        log_hint "upgrade: brew install neovim  /  conda install -c conda-forge neovim  /  build from source"
        return 1
    fi

    safe_link "modules/nvim/files" "$HOME/.config/nvim" || return 1

    # Plugin sync mode:
    #   restore (default) — install plugins at the versions in the committed
    #                       lazy-lock.json. Reproducible: every machine (nvim
    #                       0.10 host or 0.11 container) gets the same set.
    #   sync              — update plugins to latest within the spec AND rewrite
    #                       lazy-lock.json (run this to bump the pinned set,
    #                       then commit the new lock).
    #   skip              — leave plugins for nvim's first interactive launch.
    local mode="${ENVUP_NVIM_LAZY:-restore}"
    if [[ "$mode" == skip ]]; then
        log_info "ENVUP_NVIM_LAZY=skip — plugins install on first nvim launch"
        return 0
    fi
    local lazy_cmd="Lazy! restore"
    [[ "$mode" == sync ]] && lazy_cmd="Lazy! sync"
    # No lockfile yet (first ever run before one is committed)? Fall back to sync.
    [[ -f "$ENVUP_HOME/modules/nvim/files/lazy-lock.json" ]] || lazy_cmd="Lazy! sync"

    if [[ "${ENVUP_DRY_RUN:-0}" == 1 ]]; then
        log_info "[dry-run] would run: nvim --headless +'$lazy_cmd' +qa"
        return 0
    fi

    _nvim_bootstrap_lazy || return 1

    local budget="${ENVUP_NET_TIMEOUT_NVIM:-600}" t
    t=$(_net_timeout_bin)
    log_step "Installing nvim plugins ($lazy_cmd, ${budget}s timeout)"
    if [[ -n "$t" ]]; then "$t" -k "$ENVUP_NET_KILL_AFTER" "$budget" nvim --headless "+$lazy_cmd" +qa
    else nvim --headless "+$lazy_cmd" +qa; fi
    local rc=$?
    if (( rc != 0 )); then
        log_error "$lazy_cmd failed (exit $rc)"
        log_hint "check network/GitHub access, then: ENVUP_NET_TIMEOUT_NVIM=900 envup install nvim"
        log_hint "or manually: git clone ... lazy.nvim && nvim --headless \"+$lazy_cmd\" +qa"
        return 1
    fi

    log_success "nvim ready (mason installs LSP servers on first launch)"
    log_hint "per-machine overrides: ~/.config/nvim/local.lua (gitignored)"
    log_hint "bump the pinned plugin set: ENVUP_NVIM_LAZY=sync envup install nvim  (then commit lazy-lock.json)"
}
_nvim_install
