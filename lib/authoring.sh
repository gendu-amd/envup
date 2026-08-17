#!/bin/bash
# ============================================
# envup — module authoring checks (`envup doctor --authoring`)
# ============================================
# Static validation of the module contract, run against the *repo* rather than
# the machine. It catches the mistakes that are invisible until the one machine
# where they matter: a package name that only exists on Debian, a bare curl that
# escapes the mirror, an install.sh left over from the v1 contract that nothing
# will ever run again.
#
# Read-only, no logs, no network. CI runs it on every push.
#
# Depends on: log.sh, module.sh
# ============================================

# authoring_module <mod> — prints the number of issues found; logs each one.
authoring_module() {
    local m="$1" dir="$ENVUP_HOME/modules/$1" n=0 f d p e src

    [[ -f "$dir/meta.sh" ]] || { log_error "[$m] no meta.sh"; echo 1; return; }
    [[ -n "$(module_meta "$m" NAME)" ]]        || { log_error "[$m] meta.sh: missing NAME"; n=$((n+1)); }
    [[ -n "$(module_meta "$m" DESCRIPTION)" ]] || { log_error "[$m] meta.sh: missing DESCRIPTION"; n=$((n+1)); }

    while IFS= read -r d; do
        [[ -n "$d" ]] || continue
        module_exists "$d" || { log_error "[$m] DEPENDS on missing module: $d"; n=$((n+1)); }
    done < <(module_meta "$m" DEPENDS)

    for f in "$dir/meta.sh" "$dir/hooks.sh"; do
        [[ -f "$f" ]] || continue
        bash -n "$f" 2>/dev/null || { log_error "[$m] $(basename "$f"): syntax error"; n=$((n+1)); }
    done

    # The v1 contract is gone: an install.sh left behind is dead code that
    # nothing will ever run, which is worse than an error.
    for f in install.sh uninstall.sh; do
        [[ -e "$dir/$f" ]] && { log_error "[$m] $f is from the old contract — move it into hooks.sh"; n=$((n+1)); }
    done

    # meta.sh is data. Anything that acts belongs in hooks.sh, where the engine
    # calls it at a defined point in the sequence rather than at source time.
    if grep -Eq '^[[:space:]]*(pkg_install|safe_link|net_run|net_fetch|net_clone|submodule_ensure)\b' "$dir/meta.sh"; then
        log_error "[$m] meta.sh runs install steps — meta.sh is declarative, use hooks.sh"; n=$((n+1))
    fi

    # Every byte envup pulls goes through lib/net.sh, which is where the
    # mirror, the proxy, the offline check and the timeout live. A hand-rolled
    # download in a module silently escapes all four.
    for f in "$dir/meta.sh" "$dir/hooks.sh"; do
        [[ -f "$f" ]] || continue
        # Comments stripped first: several modules legitimately *mention* curl
        # in a SELF_DEPS note, and a linter that cries wolf gets switched off.
        if sed 's/#.*//' "$f" | grep -Eq '(^|[^[:alnum:]_./-])(curl|wget)[[:space:]]|git[[:space:]]+clone'; then
            log_error "[$m] $(basename "$f"): bare curl/wget/git clone — use net_fetch / net_clone"; n=$((n+1))
        fi
    done

    while IFS= read -r e; do
        [[ -n "$e" ]] || continue
        case "$e" in
            system|github_release|git|script|manual|*:*) ;;
            *) log_error "[$m] unknown provider: $e"; n=$((n+1)) ;;
        esac
    done < <(module_meta "$m" PROVIDERS)

    local opt
    while IFS= read -r e; do
        [[ -n "$e" ]] || continue
        opt=0; [[ "$e" == '?'* ]] && { opt=1; e="${e#\?}"; }
        src="${e%%:*}"
        if [[ "$src" == "$e" ]]; then
            log_error "[$m] malformed LINKS entry (want 'src:dst'): $e"; n=$((n+1)); continue
        fi
        # '?' means the module already said missing is fine — a hosts/<hostname>
        # file exists on the one machine it describes and nowhere else, so
        # warning about it would fire on every other machine, forever.
        (( opt )) || [[ -e "$ENVUP_HOME/$src" ]] ||
            log_warn "[$m] LINKS source does not exist: $src"
    done < <(module_meta "$m" LINKS)

    while IFS= read -r p; do
        case "$p" in
            *".local/share/atuin"*|*".local/share/zoxide"*|*resurrect*|*".atuin"*|*".zsh_history"*|*".bash_history"*)
                log_error "[$m] CLEAN_PATHS includes user data (clean must never delete it): $p"; n=$((n+1)) ;;
        esac
    done < <(module_meta "$m" CLEAN_PATHS)

    echo "$n"
}

# authoring_main [module...] — check every module, or the named ones.
authoring_main() {
    local -a mods=("$@")
    (( ${#mods[@]} )) || mapfile -t mods < <(modules_available)

    local total=0 m one
    for m in "${mods[@]}"; do
        one="$(authoring_module "$m")"
        total=$((total + one))
    done

    echo
    if (( total )); then
        log_error "doctor: $total authoring issue(s) found"
        return 1
    fi
    log_success "doctor: all modules OK (${#mods[@]} checked)"
}
