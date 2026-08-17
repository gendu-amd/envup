#!/usr/bin/env bats
# "Come back to what I was doing before the machine went down."
#
# Three pieces have to line up for that: resurrect must save somewhere this
# machine alone owns, something must start a tmux server when you log in, and
# nvim must leave a session behind for the panes to be restored from. Each of
# them fails silently when it is wrong — you find out weeks later, on the one
# morning it mattered — so they are tested by running them, not by reading them.

load '../test_helper'

TMUX_CONF() { printf '%s' "$REPO_ROOT/modules/tmux/files/.tmux.conf"; }
SLICE()     { printf '%s' "$REPO_ROOT/modules/zsh/files/.zshrc.d/90-tmux.zsh"; }
SESS_LUA()  { printf '%s' "$REPO_ROOT/modules/nvim/files/lua/configs/session.lua"; }

setup() {
    common_setup

    # A tmux that records what it was asked to do instead of doing it. Session
    # existence is driven by $TMUX_SESSIONS: the file holds the number of
    # has-session calls still to fail, so a test can say "the third check is
    # when the restore lands".
    stub_bin tmux <<'EOF'
#!/bin/bash
printf 'tmux %s\n' "$*" >> "$TMUX_CALLS"
case "$1" in
    has-session)
        n="$(cat "$TMUX_SESSIONS" 2>/dev/null || echo 999)"
        if [[ "$n" -le 0 ]]; then exit 0; fi
        echo $(( n - 1 )) > "$TMUX_SESSIONS"
        exit 1 ;;
    show-option|show) exit 0 ;;                 # no @resurrect-dir set
esac
exit 0
EOF
    export TMUX_CALLS="$TEST_TMP/tmux-calls"      ; : > "$TMUX_CALLS"
    export TMUX_SESSIONS="$TEST_TMP/tmux-sessions"; echo 999 > "$TMUX_SESSIONS"

    # Run the slice on a real terminal. zsh ships its own pty, which is the only
    # way to exercise a login hook whose whole job is to decide whether it is
    # talking to a person — under bats stdin is a pipe and every guard trips.
    cat > "$TEST_TMP/onpty" <<'EOF'
#!/usr/bin/env zsh
zmodload zsh/zpty
# (q): zpty re-splits its command on whitespace, so `-c 'source /path'` arrives
# as two words and zsh runs `-c source` with the path as $0.
zpty p ${(q)@}
typeset l
while zpty -r p l; do print -rn -- "$l"; done
zpty -d p
EOF
    chmod +x "$TEST_TMP/onpty"

    unset TMUX STY TERM_PROGRAM NO_TMUX ENVUP_TMUX_AUTOATTACH INSIDE_EMACS
    export TERM=xterm
    # Short waits: these tests are about which branch is taken, not how patient
    # it is. 1 => five 200ms polls.
    export ENVUP_TMUX_RESTORE_WAIT=1
}
teardown() { common_teardown; }

# `zsh -f` so the slice is the only thing loaded; `-i` because the first guard
# it applies is "am I an interactive shell".
login_shell() {
    run "$TEST_TMP/onpty" zsh -f -i -c "source $(SLICE)"
}

saved_layout() {   # pretend resurrect has something to restore
    local d="$HOME/.local/share/tmux/resurrect"
    mkdir -p "$d"
    : > "$d/a.txt"
    ln -sf a.txt "$d/last"
}

# ---- where the saves go --------------------------------------------------

@test "the resurrect store is keyed by machine, not shared across them" {
    # A home directory on NFS means every machine writes the same save file and
    # the last one to save wins: you log into the build box and get the layout
    # you left on the GPU box. This is the line that prevents it.
    grep -q '@resurrect-dir.*\$HOSTNAME' "$(TMUX_CONF)"
}

@test "the \$HOSTNAME in @resurrect-dir survives tmux's parser" {
    # In double quotes tmux expands variables itself, and $HOSTNAME is not in
    # the server's environment — the option would come out as a bare directory
    # and every machine would share it again. Single quotes are load-bearing.
    grep -q "@resurrect-dir '" "$(TMUX_CONF)"

    command -v tmux >/dev/null 2>&1 || skip "tmux not installed"
    rm -f "$STUB_BIN/tmux"            # the real tmux, not this file's stub
    # One command list: tmux before 3.0 shuts the server down again the moment
    # `start-server` leaves it with no sessions.
    local sock="envup-rd-$$"
    run tmux -L "$sock" -f "$(TMUX_CONF)" start-server \; show -gv @resurrect-dir \; kill-server
    tmux -L "$sock" kill-server 2>/dev/null || true
    [[ "$output" == *'$HOSTNAME'* ]]
}

@test "two machines sharing a home get two different save directories" {
    # The end-to-end version of the two above, run through resurrect's own
    # expansion rather than a copy of it here.
    command -v tmux >/dev/null 2>&1 || skip "tmux not installed"
    rm -f "$STUB_BIN/tmux"
    export TMUX_TMPDIR="$TEST_TMP"    # so helpers.sh's bare `tmux` finds ours

    local rs="$REPO_ROOT/modules/tmux/files/plugins/tmux-resurrect"
    [ -r "$rs/scripts/helpers.sh" ] || skip "tmux-resurrect submodule not checked out"

    # A session, not just start-server: older tmux exits a sessionless server
    # immediately, and helpers.sh has to be able to ask it for the option.
    tmux -f "$(TMUX_CONF)" new-session -d -s probe 2>/dev/null ||
        skip "cannot start a tmux server here"

    local a b
    stub_bin hostname <<<'#!/bin/bash
echo boxA'
    a="$(bash -c 'source "$1" >/dev/null 2>&1; resurrect_dir' _ "$rs/scripts/helpers.sh")"
    stub_bin hostname <<<'#!/bin/bash
echo boxB'
    b="$(bash -c 'source "$1" >/dev/null 2>&1; resurrect_dir' _ "$rs/scripts/helpers.sh")"
    tmux kill-server 2>/dev/null || true

    [ "$a" != "$b" ]
    [[ "$a" == *boxA ]]
    [[ "$b" == *boxB ]]
}

@test "an unplanned reboot costs at most five minutes of layout" {
    grep -q "@continuum-save-interval '5'" "$(TMUX_CONF)"
    grep -q "@continuum-restore 'on'"      "$(TMUX_CONF)"
}

# ---- who starts the server -----------------------------------------------

@test "a shell with no terminal never reaches for tmux" {
    # scp, rsync, `ssh box some-command`, and every test harness. Starting a
    # multiplexer under any of them breaks the caller.
    run zsh -f -i -c "source $(SLICE)"
    [ ! -s "$TMUX_CALLS" ]
}

@test "on a real terminal it starts the server and attaches" {
    login_shell
    grep -q 'tmux start-server' "$TMUX_CALLS"
    grep -qE 'tmux (attach|new-session)' "$TMUX_CALLS"
}

@test "NO_TMUX=1 is the escape hatch for one connection" {
    NO_TMUX=1 login_shell
    [ ! -s "$TMUX_CALLS" ]
}

@test "NO_TMUX beats the force switch — an escape hatch that can be overridden is not one" {
    NO_TMUX=1 ENVUP_TMUX_AUTOATTACH=1 login_shell
    [ ! -s "$TMUX_CALLS" ]
}

@test "ENVUP_TMUX_AUTOATTACH=0 turns it off for a machine" {
    ENVUP_TMUX_AUTOATTACH=0 login_shell
    [ ! -s "$TMUX_CALLS" ]
}

@test "a shell already inside tmux does not start a second one" {
    # Without this the pane's own shell attaches to the session it lives in.
    TMUX="/tmp/fake,1,0" login_shell
    [ ! -s "$TMUX_CALLS" ]
}

@test "an editor's integrated terminal is left alone, unless asked" {
    # VS Code and Cursor open several terminals at once and already have tabs.
    TERM_PROGRAM=vscode login_shell
    [ ! -s "$TMUX_CALLS" ]

    : > "$TMUX_CALLS"
    TERM_PROGRAM=vscode ENVUP_TMUX_AUTOATTACH=1 login_shell
    grep -q 'tmux' "$TMUX_CALLS"
}

@test "a machine without tmux logs in silently" {
    rm -f "$STUB_BIN/tmux"
    isolate_path
    login_shell
    [[ "$output" != *"not found"* ]]
    [[ "$output" != *"command not found"* ]]
}

@test "an existing server is joined, not restarted" {
    echo 0 > "$TMUX_SESSIONS"        # a session is already there
    login_shell
    ! grep -q 'start-server' "$TMUX_CALLS"
    grep -q 'tmux attach' "$TMUX_CALLS"
}

# ---- the race with continuum ---------------------------------------------

@test "with nothing saved it does not sit waiting for a restore that will not come" {
    # continuum only restores when there is a save file. A first login must not
    # pay the timeout to find that out.
    local t0 t1
    t0="$(date +%s)"
    login_shell
    t1="$(date +%s)"
    grep -q 'new-session -s main' "$TMUX_CALLS"
    [ "$(( t1 - t0 ))" -lt 3 ]
}

@test "it waits for continuum's restore instead of racing it into an empty session" {
    # continuum restores asynchronously — it sleeps a second first so tmux can
    # finish sourcing its plugins. Creating our own session in that gap leaves
    # you staring at an empty shell with the real work restored behind it.
    saved_layout
    echo 3 > "$TMUX_SESSIONS"        # the restore lands on the third check
    login_shell
    grep -q 'start-server' "$TMUX_CALLS"
    ! grep -q 'new-session' "$TMUX_CALLS"
    grep -q 'tmux attach' "$TMUX_CALLS"
}

@test "a restore that never arrives still gets you a shell" {
    saved_layout
    login_shell                       # has-session never succeeds
    grep -q 'new-session -s main' "$TMUX_CALLS"
}

@test "the session it falls back to can be named" {
    ENVUP_TMUX_SESSION=work login_shell
    grep -q 'new-session -s work' "$TMUX_CALLS"
}

@test "the slice loads after the per-machine ones that may switch it off" {
    local d="$REPO_ROOT/modules/zsh/files/.zshrc.d"
    [ -f "$d/90-tmux.zsh" ]
    # 70-host and 80-local both sort before it, which is the only reason
    # ENVUP_TMUX_AUTOATTACH=0 in either of them has any effect.
    [ "$(printf '%s\n' 70-host.zsh 80-local.zsh 90-tmux.zsh | sort | tail -1)" = 90-tmux.zsh ]
}

# ---- nvim's half ----------------------------------------------------------

@test "session.lua is valid lua" {
    command -v luajit >/dev/null 2>&1 || command -v lua5.1 >/dev/null 2>&1 ||
        command -v lua >/dev/null 2>&1 || skip "no lua interpreter"
    local lua; lua="$(command -v luajit || command -v lua5.1 || command -v lua)"
    run "$lua" -e "assert(loadfile('$(SESS_LUA)'))"
    [ "$status" -eq 0 ]
}

@test "the session is written on a timer, not on exit" {
    # A kernel going down does not run VimLeavePre. Saving only on exit would
    # preserve every session except the ones this feature exists for.
    grep -q 'new_timer' "$(SESS_LUA)"
    grep -q 'INTERVAL_MS' "$(SESS_LUA)"
}

@test "a clean quit takes the session file with it" {
    # Otherwise every project directory you ever opened keeps a Session.vim.
    grep -q 'VimLeavePre' "$(SESS_LUA)"
    grep -q 'fs_unlink'   "$(SESS_LUA)"
}

@test "nothing is written outside tmux" {
    grep -q 'vim.env.TMUX' "$(SESS_LUA)"
}

@test "the file lands where tmux-resurrect looks for it" {
    # The strategy checks "${DIRECTORY}/Session.vim" and nowhere else — see
    # plugins/tmux-resurrect/strategies/nvim_session.sh. Renaming it here would
    # break the restore with no error anywhere.
    grep -q 'SESSION_FILE = "Session.vim"' "$(SESS_LUA)"
    grep -q 'getcwd' "$(SESS_LUA)"
    grep -q "@resurrect-strategy-nvim 'session'" "$(TMUX_CONF)"
}

@test "nvim actually loads it" {
    grep -q 'require("configs.session").setup()' "$REPO_ROOT/modules/nvim/files/init.lua"
}

@test "a Session.vim left behind by a crash does not show up in git status" {
    grep -qx 'Session.vim' "$REPO_ROOT/modules/git/files/ignore"
    # ~/.config/git/ignore is a path git reads on its own — no core.excludesFile
    # to get wrong, and nothing to include from .gitconfig.
    grep -q 'modules/git/files/ignore:\$HOME/.config/git/ignore' "$REPO_ROOT/modules/git/meta.sh"
}
