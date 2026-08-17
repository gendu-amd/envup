# ============================================
# 90 — pick up where you left off
# ============================================
# tmux-resurrect saves the session tree every few minutes and tmux-continuum
# restores it whenever a tmux server starts. The half that was missing: after a
# reboot nothing ever started a server. You logged in, got a bare shell, and had
# to remember that your layout was sitting in a file waiting for you to type
# `tmux`. This slice types it.
#
# It is numbered last on purpose. Slices 70 (hosts/<machine>.zsh) and 80
# (~/.zshrc.local) load first, so either can turn this off for a machine where
# it is the wrong behaviour.
#
#   NO_TMUX=1 ssh box          just this once
#   ENVUP_TMUX_AUTOATTACH=0    this machine, never
#   ENVUP_TMUX_AUTOATTACH=1    force it on where a guard below says no
#   ENVUP_TMUX_SESSION=name    what to create when there is nothing to restore
#
# It does not exec. Detaching leaves you in a normal shell instead of dropping
# the connection, and a tmux that refuses to start cannot lock you out of the
# machine — which matters more here than the one saved process, because the
# machine this runs on is usually one you can only reach over SSH.

# Where tmux-resurrect keeps its saves. Asked rather than recomputed: resurrect
# expands $HOME/$HOSTNAME/~ inside @resurrect-dir, honours a value set from
# ~/.tmux/host.conf, and has a legacy location it still prefers if it exists.
# A second copy of those rules here would drift, and this is the copy that would.
_envup_resurrect_dir() {
    local helpers="$HOME/.tmux/plugins/tmux-resurrect/scripts/helpers.sh" dir=
    if [[ -r "$helpers" ]] && command -v bash >/dev/null 2>&1; then
        dir="$(bash -c 'source "$1" >/dev/null 2>&1; resurrect_dir' _ "$helpers" 2>/dev/null)"
    fi
    print -r -- "${dir:-${XDG_DATA_HOME:-$HOME/.local/share}/tmux/resurrect}"
}

() {
    local force="${ENVUP_TMUX_AUTOATTACH:-}"

    # Kill switches first — these win over everything, including force.
    [[ -n "${NO_TMUX:-}" ]] && return 0
    [[ "$force" == 0 ]] && return 0

    # Hard guards. Getting any of these wrong is how a login hook turns into a
    # machine you cannot log into, so force does not skip them.
    [[ -o interactive ]]            || return 0
    [[ -z "${TMUX:-}${STY:-}" ]]    || return 0   # already inside tmux or screen
    [[ -t 0 && -t 1 ]]              || return 0   # `ssh box cmd`, scp, rsync, a test
    [[ "${TERM:-dumb}" != dumb ]]   || return 0
    command -v tmux >/dev/null 2>&1 || return 0

    if [[ "$force" != 1 ]]; then
        # An editor opens several terminals at once and already has tabs for
        # them; every one of them attaching to the same session is a mess. This
        # covers VS Code and Cursor, local and over Remote-SSH alike. Type
        # `tmux a` in one of them when you do want it.
        [[ "${TERM_PROGRAM:-}" != vscode ]] || return 0
        [[ -z "${INSIDE_EMACS:-}" ]]        || return 0
    fi

    # A server is already up — another connection, or you just detached from
    # this one. Nothing to restore, just join it.
    if tmux has-session 2>/dev/null; then
        tmux attach
        return 0
    fi

    # No server. Starting one is what triggers continuum's restore, but that
    # restore is asynchronous: continuum sleeps a second so tmux can finish
    # sourcing its plugins, then rebuilds the sessions one at a time. Creating
    # our own session in that window would land us in an empty shell with the
    # real work quietly restored behind it.
    tmux start-server 2>/dev/null || return 0

    # So wait — but only when there is something to wait for. With no save file
    # the restore is a no-op and every first login would pay the full timeout
    # for nothing.
    if [[ -e "$(_envup_resurrect_dir)/last" ]]; then
        local -i ticks=0 limit=$(( ${ENVUP_TMUX_RESTORE_WAIT:-8} * 5 )) nap_ok=0
        # zselect is the sub-second sleep that is always there: it ships with
        # zsh, whereas `sleep 0.2` is whole-seconds on a few systems. It exits
        # 1 when the timeout expires with no descriptor ready, which is every
        # call here, so its status is deliberately ignored.
        zmodload -i zsh/zselect 2>/dev/null && nap_ok=1
        until tmux has-session 2>/dev/null || (( ticks >= limit )); do
            if (( nap_ok )); then
                zselect -t 20 2>/dev/null
            else
                sleep 0.2 2>/dev/null || sleep 1
            fi
            (( ++ticks ))
        done
        # Attaching while the restore is still running is fine and looks good —
        # you watch the windows arrive. Waiting for it to *finish* would mean
        # guessing at how long, which is worse than joining early.
    fi

    if tmux has-session 2>/dev/null; then
        tmux attach
    else
        tmux new-session -s "${ENVUP_TMUX_SESSION:-main}"
    fi
}
