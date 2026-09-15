#!/bin/bash
# nvim hooks: bootstrap lazy.nvim and materialise the pinned plugin set.
#
# ENVUP_NVIM_LAZY selects what happens to plugins:
#   restore (default) — install exactly what lazy-lock.json pins. Reproducible
#                       across machines, which is the whole point of the lock.
#   sync              — update within the spec AND rewrite the lock (then commit it).
#   skip              — skip plugin and language-tool provisioning explicitly.

pre_install() {
    case "$ENVUP_LIBC" in
        glibc-*)
            if ! version_ge "${ENVUP_LIBC#glibc-}" "$NVIM_RELEASE_GLIBC_MIN"; then
                # shellcheck disable=SC2034  # consumed later by the release provider
                GH_TAG="$NVIM_LEGACY_TAG"
            fi
            ;;
    esac
}

_nvim_bootstrap_lazy() {
    local data="${XDG_DATA_HOME:-$HOME/.local/share}/nvim"
    local lazy="$data/lazy/lazy.nvim"

    [[ -f "$lazy/lua/lazy/init.lua" ]] && return 0
    # A warning, not an error: post_install turns this into 'degraded', and nvim
    # itself is perfectly usable without its plugin set.
    have git || { log_warn "nvim plugins need git on PATH"; return 1; }

    # A file or a broken symlink at $data blocks mkdir — the "File exists"
    # failure seen on fresh WSL installs.
    [[ -d "$data" ]] || rm -f "$data"
    mkdir -p "$(dirname "$lazy")"
    [[ -d "$lazy" ]] && rm -rf "$lazy"

    log_step "bootstrapping lazy.nvim"
    net_clone "https://github.com/folke/lazy.nvim.git" "$lazy" --filter=blob:none --branch=stable \
        || { log_error "cloning lazy.nvim failed"; return 1; }
    [[ -f "$lazy/lua/lazy/init.lua" ]] || { log_error "lazy.nvim missing after clone"; return 1; }
}

_nvim_headless() {
    local budget="${ENVUP_NET_TIMEOUT_NVIM:-600}" t
    t="$(timeout_bin)"
    if [[ -n "$t" ]]; then "$t" -k "$ENVUP_NET_KILL_AFTER" "$budget" nvim --headless "$@" +qa
    else                   nvim --headless "$@" +qa; fi
}

post_install() {
    local mode="${ENVUP_NVIM_LAZY:-restore}"
    if [[ "$mode" == skip ]]; then
        log_info "ENVUP_NVIM_LAZY=skip — skipping plugins, LSP servers and formatters"
        return 0
    fi

    # Degraded (no nvim, or one older than NvChad needs): the config is linked
    # and that is the right outcome, but there is nothing here to run plugins
    # with. Bail out quietly rather than failing the module.
    if ! engine_verify; then
        log_info "skipping plugin install — no usable nvim on this machine yet"
        log_hint "once nvim >= $VERIFY_MIN_VERSION exists: envup install nvim"
        return 0
    fi

    local cmd="Lazy! restore"
    [[ "$mode" == sync ]] && cmd="Lazy! sync"
    # First run ever, before a lock is committed: there is nothing to restore.
    [[ -f "$ENVUP_HOME/modules/nvim/files/lazy-lock.json" ]] || cmd="Lazy! sync"

    if [[ "${ENVUP_DRY_RUN:-0}" == 1 ]]; then
        log_info "[dry-run] would run: nvim --headless +'$cmd' +qa"
        log_info "[dry-run] would install and verify the configured LSP servers and formatters"
        return 0
    fi

    if ! _nvim_bootstrap_lazy; then
        # nvim itself is installed and its config is linked; only the plugin
        # set is missing. Degraded, not failed — and re-running the module once
        # git exists finishes the job.
        _ENG_HOOK_REASON="nvim is installed but its plugins are not (lazy.nvim could not be fetched)"
        log_hint "install git, then: envup install nvim"
        return "$ENVUP_RC_DEGRADED"
    fi

    local budget="${ENVUP_NET_TIMEOUT_NVIM:-600}" rc
    log_step "installing nvim plugins ($cmd, ${budget}s budget)"
    _nvim_headless "+$cmd"
    rc=$?
    if (( rc != 0 )); then
        # Same reasoning as the bootstrap failure: nvim runs, the config is
        # linked, only the plugins are short. Usually a slow or blocked GitHub.
        log_warn "$cmd failed (exit $rc)"
        log_hint "check GitHub access, then: ENVUP_NET_TIMEOUT_NVIM=900 envup install nvim"
        _ENG_HOOK_REASON="nvim is installed but '$cmd' did not finish (exit $rc)"
        return "$ENVUP_RC_DEGRADED"
    fi

    log_step "installing nvim LSP servers and formatters (${budget}s budget)"
    _nvim_headless "+lua require('configs.tools').ensure()"
    rc=$?
    if (( rc != 0 )); then
        log_warn "nvim tool installation failed (exit $rc)"
        log_hint "open :Mason for details, then re-run: envup install nvim"
        _ENG_HOOK_REASON="nvim is installed but one or more LSP servers or formatters are unavailable"
        return "$ENVUP_RC_DEGRADED"
    fi

    log_success "nvim ready (plugins, LSP servers and formatters installed)"
    log_hint "per-machine overrides: ~/.config/nvim/local.lua (gitignored)"
    log_hint "bump the pinned set: ENVUP_NVIM_LAZY=sync envup install nvim, then commit lazy-lock.json"
}

post_uninstall() {
    log_info "plugin caches kept at ~/.local/share/nvim and ~/.cache/nvim"
    log_hint "to clean them: envup clean nvim"
    return 0
}
