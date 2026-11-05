#!/bin/bash
# Machine checks use shared health probes; --fix repairs links then re-checks.
# --authoring checks module contracts without repairing the machine.
# Issues fail the command; incomplete optional capabilities are notes.

_DOC_ISSUES=0
_DOC_NOTES=0
_doc_issue() { log_error "$*"; _DOC_ISSUES=$((_DOC_ISSUES + 1)); }
_doc_note()  { log_warn  "$*"; _DOC_NOTES=$((_DOC_NOTES + 1)); }

# _doctor_relink <mod> — rebuild every link the module declares. safe_link still
# backs up anything real it finds in the way, so this can be pointed at a
# 'foreign' target without losing the user's file.
_doctor_relink() { ( _engine_load "$1" >/dev/null && _engine_links ); }

# ---- the environment around envup ----------------------------------------
_doctor_env() {
    log_step "environment"
    # caps_net probes the network. doctor is the one command where spending a
    # few seconds on that is the point — "can this machine reach github" is half
    # of every install question.
    caps_net >/dev/null
    log_info "$(caps_summary)"

    # Every root-free install lands in ENVUP_LOCAL_BIN. If it is not on PATH the
    # tools are on disk and invisible, which looks exactly like "install failed".
    if [[ -d "$ENVUP_LOCAL_BIN" ]] && [[ ":$PATH:" != *":$ENVUP_LOCAL_BIN:"* ]]; then
        _doc_note "$ENVUP_LOCAL_BIN is not on PATH — anything installed there is invisible"
        log_hint "in this shell: export PATH=\"$ENVUP_LOCAL_BIN:\$PATH\"; envup's zsh startup also adds it"
    fi

    # A LANG naming a locale the machine cannot generate makes every command
    # print a setlocale warning. Common on minimal server images.
    if have locale; then
        local want="${LC_ALL:-${LANG:-}}" got norm
        if [[ -n "$want" && "$want" != C && "$want" != POSIX ]]; then
            norm="$(printf '%s' "$want" | tr '[:upper:]' '[:lower:]' | tr -d '-')"
            got="$(locale -a 2>/dev/null | tr '[:upper:]' '[:lower:]' | tr -d '-' | grep -Fx "$norm")"
            [[ -n "$got" ]] || _doc_note "locale '$want' is not available here — expect setlocale warnings"
        fi
    fi
    [[ -n "${LC_ALL:-}" ]] && _doc_note "LC_ALL is set ($LC_ALL) — it overrides every LC_* category; prefer LANG"

    # Without it, a wedged package manager or a stalled clone hangs the whole run.
    [[ -n "$(timeout_bin)" ]] || _doc_note "no 'timeout' binary — module hooks run without a watchdog (macOS: brew install coreutils)"
    return 0
}

# ---- the repo -------------------------------------------------------------
_doctor_repo() {
    log_step "repo: $ENVUP_HOME"
    local fix="$1"

    # Moving the checkout dangles every symlink at once. Recognising that is the
    # difference between one clear sentence and twenty confusing ones.
    local root; root="$(manifest_root)"
    if [[ -n "$root" ]] && ! paths_same "$root" "$ENVUP_HOME"; then
        _doc_issue "the repo moved: links were made from '$root', envup now runs from '$ENVUP_HOME'"
        if (( fix )); then
            local m
            while IFS= read -r m; do
                [[ -n "$m" ]] && module_exists "$m" && _doctor_relink "$m"
            done < <(manifest_list)
            manifest_set_root "$ENVUP_HOME"
            log_success "relinked from the new location"
        else
            log_hint "envup doctor --fix"
        fi
    fi

    # Submodules carry the zsh plugins and the tmux plugins. A clone without
    # --recursive leaves the directories there and empty, and the failure shows
    # up much later as "source not found".
    if have git && git -C "$ENVUP_HOME" rev-parse --git-dir >/dev/null 2>&1 &&
       [[ -f "$ENVUP_HOME/.gitmodules" ]]; then
        local -a empty=(); local p
        while IFS= read -r p; do
            p="${p#*.path }"
            [[ -n "$p" ]] || continue
            [[ -n "$(ls -A "$ENVUP_HOME/$p" 2>/dev/null)" ]] || empty+=("$p")
        done < <(git -C "$ENVUP_HOME" config -f .gitmodules --get-regexp '^submodule\..*\.path$' 2>/dev/null)
        if (( ${#empty[@]} )); then
            _doc_issue "${#empty[@]} submodule(s) not checked out: ${empty[*]}"
            if (( fix )); then
                net_run "git submodule" -- git -C "$ENVUP_HOME" submodule update --init --recursive ||
                    log_error "submodule checkout failed"
            else
                log_hint "git -C $ENVUP_HOME submodule update --init --recursive"
            fi
        fi
    fi

    # Managed files that differ from the commit. Not an issue: editing your own
    # dotfiles is the point of the repo, and uncommitted work is normal. But a
    # *pure append* to a tracked file is the signature of a third-party
    # installer having "helpfully" added itself, and that one is worth naming.
    #
    # Only the appends get a line each. Ordinary edits are collapsed into one
    # note with a count: mid-refactor there can be dozens of them, and thirty
    # warnings about your own work is how a real finding gets scrolled past.
    local -a rows=() plain=(); local row path
    mapfile -t rows < <(health_drift)
    if (( ${#rows[@]} )); then
        for row in "${rows[@]}"; do
            path="${row#*$'\t'}"   # row is "<git status>\t<path>"
            if adopt_appended "$path" >/dev/null 2>&1; then
                _doc_note "$path has lines appended after the last commit — a tool may have edited it"
                log_hint "move them out of the repo: envup adopt $path"
            else
                plain+=("$path")
            fi
        done
        if (( ${#plain[@]} )); then
            _doc_note "${#plain[@]} managed file(s) differ from the commit: ${plain[0]}$( (( ${#plain[@]} > 1 )) && printf ' (+%d more)' $(( ${#plain[@]} - 1 )) )"
            log_hint "see them all: git -C $ENVUP_HOME status --short -- 'modules/*/files/*'"
        fi
        log_hint "uncommitted changes are also what makes 'envup upgrade' fail its git pull"
    fi
    return 0
}

# ---- the installed modules ------------------------------------------------
_doctor_modules() {
    local fix="$1"; shift
    local -a mods=(${1+"$@"})
    (( ${#mods[@]} )) || mapfile -t mods < <({ manifest_list; manifest_install_list; } | sort -u)
    if (( ${#mods[@]} == 0 )); then
        log_step "modules"; log_info "nothing installed yet — try: envup install"
        return 0
    fi

    log_step "modules"
    local m probe state tool detail line lstate ldst last
    for m in "${mods[@]}"; do
        if ! module_exists "$m"; then
            _doc_issue "[$m] in the manifest but no such module in the repo (orphan entry)"
            if (( fix )); then manifest_remove "$m"; log_success "[$m] removed from the manifest"; fi
            continue
        fi

        probe="$(health_probe "$m")"
        state="$(health_field "$probe" state)"
        tool="$(health_field "$probe" tool)"
        detail="$(printf '%s\n' "$probe" | awk -F'\t' '$1 == "tool" { print $3; exit }')"
        case "$(health_field "$probe" check)" in
            degraded) _doc_note "[$m] $(health_field "$probe" check 3)" ;;
            broken|unknown) _doc_issue "[$m] $(health_field "$probe" check 3)" ;;
        esac
        last="$(manifest_install_get "$m" all)"
        case "$(health_field "$last" state)" in
            failed|running|degraded)
                _doc_note "[$m] last install $(health_field "$last" state) at $(health_field "$last" phase): $(health_field "$last" reason)"
                log_hint "retry the installation: envup install $m" ;;
        esac
        if [[ "$state" == absent && -n "$last" ]]; then
            log_info "[$m] not installed"; continue
        fi

        local -a broken=()
        while IFS= read -r line; do
            [[ -n "$line" ]] || continue
            lstate="${line%%$'\t'*}"; ldst="${line#*$'\t'}"; ldst="${ldst%%$'\t'*}"
            case "$lstate" in
                ok|skipped) ;;
                *) broken+=("$ldst"); _doc_issue "[$m] link $lstate: $ldst" ;;
            esac
        done < <(health_records "$probe" link)

        if (( ${#broken[@]} )) && (( fix )); then
            _doctor_relink "$m" && log_success "[$m] links rebuilt"
        fi

        case "$state" in
            ok)       log_success "[$m] ok${detail:+ ($detail)}" ;;
            degraded)
                      # Not installed here is a designed outcome on a locked-down
                      # box. Installed-but-unrunnable is not: something put a
                      # binary on this machine that cannot execute on it.
                      if [[ "$(health_field "$probe" check)" == degraded ]]; then
                          log_hint "[$m] restore missing components: envup install $m"
                      elif [[ "$tool" == broken ]]; then
                          _doc_issue "[$m] $detail"
                          log_hint "[$m] let envup pick another route: envup install $m"
                      else
                          _doc_note "[$m] degraded: ${detail:-the tool is not installed here}"
                          log_hint "the config is linked — it starts working the moment the tool exists"
                      fi ;;
            broken)   (( ${#broken[@]} )) && log_error "[$m] broken: ${#broken[@]} link(s) need attention" ;;
            absent)   log_info    "[$m] not installed" ;;
            *)        _doc_issue  "[$m] could not be read (meta.sh?)" ;;
        esac
        [[ "$tool" == old ]] && log_hint "[$m] upgrade it: envup install $m"
    done
    return 0
}

# ---- entry point ----------------------------------------------------------
# One full pass over repo + modules. Counters are reset here, so a --fix run can
# do a second, read-only pass afterwards and let *that* decide the verdict:
# "I tried to fix it" is not the same claim as "it is fixed", and only the
# second pass can make the stronger one.
_doctor_pass() {
    local fix="$1"; shift
    _DOC_ISSUES=0; _DOC_NOTES=0
    (( $# )) || _doctor_repo "$fix"
    _doctor_modules "$fix" ${1+"$@"}
}

doctor_main() {
    local fix=0 authoring=0; local -a only=()
    while (($#)); do case "$1" in
        --fix)        fix=1; shift ;;
        --authoring)  authoring=1; shift ;;
        --module)     [[ -n "${2:-}" ]] || { log_error "--module needs a name"; return 1; }
                      only+=("$2"); shift 2 ;;
        -h|--help) cat <<'EOF'
Usage: envup doctor [--fix] [--authoring] [--module NAME]
  (default)      health-check this machine: links, tools, manifest, repo
  --fix          repair what can be repaired (rebuild links, drop orphans)
  --authoring    validate module authoring conventions in the repo instead
  --module NAME  restrict to one module (repeatable)
EOF
            return 0 ;;
        -*) log_error "unknown option: $1"; return 1 ;;
        *)  only+=("$1"); shift ;;
    esac; done

    local m
    for m in "${only[@]+"${only[@]}"}"; do
        module_exists "$m" || { log_error "no such module: $m"; return 1; }
    done

    if (( authoring )); then
        authoring_main "${only[@]+"${only[@]}"}"
        return $?
    fi

    # --fix rebuilds links and drops manifest orphans, so this run has to leave
    # the same record every other machine-changing command leaves. A plain
    # health check logs too — a diagnosis is worth keeping next to the repair.
    log_init doctor

    _DOC_ISSUES=0; _DOC_NOTES=0
    _doctor_env
    local env_notes=$_DOC_NOTES

    _doctor_pass "$fix" "${only[@]+"${only[@]}"}"
    if (( fix && _DOC_ISSUES )); then
        echo; log_step "re-checking after repair"
        _doctor_pass 0 "${only[@]+"${only[@]}"}"
    fi
    _DOC_NOTES=$((_DOC_NOTES + env_notes))

    echo
    if (( _DOC_ISSUES )); then
        log_error "doctor: $_DOC_ISSUES issue(s), $_DOC_NOTES note(s)"
        (( fix )) || log_hint "repair what can be repaired: envup doctor --fix"
        return 1
    fi
    if (( _DOC_NOTES )); then
        log_success "doctor: this machine is healthy ($_DOC_NOTES note(s) above)"
    else
        log_success "doctor: this machine is healthy"
    fi
    return 0
}
