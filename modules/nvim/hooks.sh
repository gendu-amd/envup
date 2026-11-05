#!/bin/bash
# Bootstrap lazy.nvim, restore pinned plugins, and install language tools.

pre_install() {
    _nvim_config_root || return 1
    case "$ENVUP_LIBC" in
        glibc-*)
            if ! version_ge "${ENVUP_LIBC#glibc-}" "$NVIM_RELEASE_GLIBC_MIN"; then
                # shellcheck disable=SC2034  # consumed later by the release provider
                GH_TAG="$NVIM_LEGACY_TAG"
            fi
            ;;
    esac
}

_nvim_config_root() {
    local dst="${XDG_CONFIG_HOME:-$HOME/.config}/nvim" bak="" stage private
    [[ -d "$dst" && ! -L "$dst" ]] && return 0
    if [[ -L "$dst" ]] && ! paths_same "$dst" "$ENVUP_HOME/modules/nvim/files"; then
        log_error "nvim config points outside this checkout: $dst"
        log_hint "move the directory link aside and preserve your local.lua before retrying"
        return 1
    fi
    if [[ "${ENVUP_DRY_RUN:-0}" == 1 ]]; then
        log_info "[dry-run] prepare real nvim config directory: $dst"
        return 0
    fi
    mkdir -p "${dst%/*}" || return 1
    stage="$(mktemp -d "${dst}.envup.XXXXXX")" || return 1
    # Copy before moving the legacy link so a failed copy leaves it usable.
    # A fresh install must never import another user's checkout-local file.
    if [[ -L "$dst" ]]; then
        for private in local.lua envup.json; do
            [[ -e "$dst/$private" || -L "$dst/$private" ]] || continue
            if [[ ! -f "$dst/$private" ]] || ! cp -L "$dst/$private" "$stage/$private"; then
                rm -rf "$stage"
                log_error "cannot preserve nvim $private: $dst/$private"
                return 1
            fi
        done
    fi
    if [[ -e "$dst" || -L "$dst" ]]; then
        bak="$(backup_path "$dst")"
        if [[ -e "$bak" || -L "$bak" ]] || ! mkdir -p "${bak%/*}" || ! mv "$dst" "$bak"; then
            rm -rf "$stage"
            log_error "cannot back up nvim config: $dst"
            return 1
        fi
        log_info "backup: $dst -> $bak"
    fi
    if ! mv "$stage" "$dst"; then
        [[ -n "$bak" ]] && mv "$bak" "$dst"
        rm -rf "$stage"
        return 1
    fi
}

_nvim_bootstrap_lazy() {
    local data="${XDG_DATA_HOME:-$HOME/.local/share}/nvim"
    local lazy="$data/lazy/lazy.nvim"

    [[ -f "$lazy/lua/lazy/init.lua" ]] && return 0
    if ! net_online; then
        log_warn "offline: keeping incomplete lazy.nvim cache at $lazy"
        return "$ENVUP_RC_OFFLINE"
    fi
    have git || { log_warn "nvim plugins need git on PATH"; return "$ENVUP_RC_DEGRADED"; }

    # A file or dangling link at $data would block mkdir.
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

_nvim_plugins_enabled() {
    local p; p="$(bin_path nvim)" || return 1
    NVIM_LOG_FILE=/dev/null "$p" --headless -u NONE -i NONE -n --noplugin \
        '+lua local ok, enabled = pcall(function() return dofile(vim.env.ENVUP_HOME .. "/modules/nvim/files/lua/configs/tools.lua").plugins_enabled() end); if not ok then print(enabled); vim.cmd("cquit 1") elseif not enabled then vim.cmd("cquit 70") end' +qa
}

post_install() {
    local mode="${ENVUP_NVIM_LAZY:-restore}" rc
    if [[ "$mode" == skip ]]; then
        log_info "ENVUP_NVIM_LAZY=skip — skipping plugins, LSP servers and formatters"
        return 0
    fi

    if ! engine_verify; then
        log_info "skipping plugin install — no usable nvim on this machine yet"
        log_hint "once nvim >= $VERIFY_MIN_VERSION exists: envup install nvim"
        return 0
    fi

    local profile_rc=0
    _nvim_plugins_enabled || profile_rc=$?
    if (( profile_rc == ENVUP_RC_DEGRADED )); then
        log_info "nvim core mode — plugin and language-tool installation disabled by envup.json"
        return 0
    elif (( profile_rc != 0 )); then
        log_error "could not read nvim capability selection from envup.json"
        return 1
    fi

    local action=restore
    [[ "$mode" == sync ]] && action=sync
    [[ -f "$ENVUP_HOME/modules/nvim/files/lazy-lock.json" ]] || action=sync
    local cmd="Lazy! $action"

    if [[ "${ENVUP_DRY_RUN:-0}" == 1 ]]; then
        log_info "[dry-run] would run: nvim --headless +'$cmd' +qa"
        log_info "[dry-run] would install and verify the configured LSP servers and formatters"
        return 0
    fi

    if [[ "${ENVUP_NET:-auto}" == offline || "${ENVUP_OFFLINE:-0}" == 1 ]]; then
        local details=""
        rc=0
        details="$(check_health)" || rc=$?
        if (( rc == 0 )); then
            log_info "offline: using cached nvim components without restore or sync"
            return 0
        fi
        _ENG_HOOK_REASON="${details:-nvim cached components could not be checked}"
        log_warn "$_ENG_HOOK_REASON"
        log_hint "run envup install nvim when online; core editing is available without plugins"
        (( rc == ENVUP_RC_DEGRADED )) && return "$ENVUP_RC_DEGRADED"
        return 1
    fi

    rc=0
    _nvim_bootstrap_lazy || rc=$?
    if (( rc != 0 )); then
        _ENG_HOOK_REASON="nvim lazy.nvim bootstrap did not finish (exit $rc)"
        log_warn "$_ENG_HOOK_REASON"
        log_hint "check Git and network access, then: envup install nvim"
        if (( rc == ENVUP_RC_DEGRADED || rc == ENVUP_RC_OFFLINE )); then
            return "$ENVUP_RC_DEGRADED"
        fi
        return 1
    fi

    local budget="${ENVUP_NET_TIMEOUT_NVIM:-600}"
    log_step "installing nvim plugins ($cmd, ${budget}s budget)"
    _nvim_headless --cmd "lua local ok, err = pcall(function() dofile(vim.env.ENVUP_HOME .. '/modules/nvim/files/lua/configs/tools.lua').prepare_lock('$action' == 'restore') end); if not ok then print(err); vim.cmd('cquit 1') end" \
        "+lua local ok, err = pcall(function() require('configs.tools').ensure_plugins('$action') end); if not ok then print(err); vim.cmd('cquit 1') end"
    rc=$?
    if (( rc != 0 )); then
        log_warn "$cmd failed (exit $rc)"
        log_hint "check GitHub access, then: ENVUP_NET_TIMEOUT_NVIM=900 envup install nvim"
        _ENG_HOOK_REASON="nvim is installed but '$cmd' did not finish (exit $rc)"
        return 1
    fi

    log_step "installing nvim LSP servers and formatters (${budget}s budget)"
    _nvim_headless "+lua require('configs.tools').ensure()"
    rc=$?
    if (( rc != 0 )); then
        log_warn "nvim tool installation failed (exit $rc)"
        log_hint "open :Mason for details, then re-run: envup install nvim"
        _ENG_HOOK_REASON="nvim language-tool installation failed (exit $rc); installed components were kept"
        return 1
    fi

    log_step "installing and verifying nvim parsers (${budget}s budget)"
    _nvim_headless "+lua require('configs.tools').ensure_parsers()"
    rc=$?
    if (( rc != 0 )); then
        _ENG_HOOK_REASON="nvim parser installation failed (exit $rc); installed components were kept"
        log_error "$_ENG_HOOK_REASON"
        return 1
    fi

    log_success "nvim ready (plugins, LSP servers, formatters and parsers verified)"
    log_hint "private overrides: ${XDG_CONFIG_HOME:-$HOME/.config}/nvim/local.lua"
    log_hint "update the user-state plugin lock: ENVUP_NVIM_LAZY=sync envup install nvim"
}

check_health() {
    [[ "${ENVUP_NVIM_LAZY:-restore}" == skip ]] && return 0
    local p; p="$(bin_path nvim)" || return 1
    # Inspect components without user init; even -u NONE can create a log.
    NVIM_LOG_FILE=/dev/null "$p" --headless -u NONE -i NONE -n --noplugin \
        '+lua local ok, err = pcall(function() dofile(vim.env.ENVUP_HOME .. "/modules/nvim/files/lua/configs/tools.lua").check() end); if not ok then print(err); vim.cmd("cquit 1") end' +qa
}

post_uninstall() {
    log_info "plugin installations, language tools, and editor state are kept"
    log_hint "envup clean nvim removes declared caches only; plugins are preserved"
    return 0
}
