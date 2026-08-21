#!/usr/bin/env bats
# "Come back to what I was doing before the machine went down."
#
# Three pieces have to line up for that: resurrect must save somewhere this
# machine alone owns, the command you type must not race continuum's restore
# into an empty session, and nvim must leave a session behind for the panes to
# be restored from. Each of them fails silently when it is wrong — you find out
# weeks later, on the one morning it mattered — so they are tested by running
# them, not by reading them.

load '../test_helper'

TMUX_CONF() { printf '%s' "$REPO_ROOT/modules/tmux/files/.tmux.conf"; }
RESUME()    { printf '%s' "$REPO_ROOT/modules/tmux/files/bin/tmux-resume"; }
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

    unset TMUX STY
    export TERM=xterm
    # Short waits: these tests are about which branch is taken, not how patient
    # it is. 1 => five 200ms polls.
    export ENVUP_TMUX_RESTORE_WAIT=1
}
teardown() { common_teardown; }

resume() { run "$(RESUME)" "$@"; }

saved_layout() {   # pretend resurrect has something to restore
    local d="$HOME/.local/share/tmux/resurrect"
    mkdir -p "$d"
    : > "$d/a.txt"
    ln -sf a.txt "$d/last"
}

# ---- where the saves go --------------------------------------------------

# The @resurrect-dir a real tmux is left holding once it has read the config.
# What the file says is only the input: the value goes through tmux's parser on
# the way in and tmux-resurrect's sed on the way out, and the bug these guard
# lived in the gap between the two. So ask the server, not the file.
conf_resurrect_dir() {   # <what `hostname` prints> [socket tag]
    export TMUX_TMPDIR="$TEST_TMP"        # sockets under the test dir, not /tmp
    rm -f "$STUB_BIN/tmux"                # the real tmux, not setup()'s recorder
    stub_bin hostname <<EOF
#!/bin/bash
printf '%s\n' '$1'
EOF
    local sock="envup-rd-$$-${2:-a}"
    # A session, not just start-server: tmux before 3.0 shuts a server back down
    # the moment it is left with none.
    tmux -L "$sock" -f "$(TMUX_CONF)" new-session -d 2>/dev/null || return 1
    tmux -L "$sock" show-option -gqv @resurrect-dir
    tmux -L "$sock" kill-server 2>/dev/null || true
}

@test "the resurrect store is keyed by machine, not shared across them" {
    # A home directory on NFS means every machine writes the same save file and
    # the last one to save wins: you log into the build box and get the layout
    # you left on the GPU box.
    command -v tmux >/dev/null 2>&1 || skip "tmux not installed"
    local a b
    a="$(conf_resurrect_dir boxA a)" || skip "cannot start a tmux server here"
    b="$(conf_resurrect_dir boxB b)"
    [ "$a" != "$b" ]
    [[ "$a" == */boxA ]]
    [[ "$b" == */boxB ]]
}

@test "the save directory is handed over already expanded" {
    # The regression. The option used to hold the literal string
    # '$HOME/.local/share/tmux/resurrect/$HOSTNAME' and leave the expanding to
    # resurrect's sed at save time. On one tmux the value came back from that
    # round trip as '\$HOME/...\$HOSTNAME'; sed rewrote the $HOME inside it and
    # left the backslash, so every save went to a directory literally named '\'
    # in the home directory — while the restore kept reading the real path and
    # finding a month-old layout. Nothing there is reachable once the value
    # arrives with nothing left to expand.
    command -v tmux >/dev/null 2>&1 || skip "tmux not installed"
    local dir; dir="$(conf_resurrect_dir boxA)" || skip "cannot start a tmux server here"
    [ -n "$dir" ]
    [[ "$dir" == /*    ]]
    [[ "$dir" != *'$'* ]]
    [[ "$dir" != *'~'* ]]
    [[ "$dir" != *'\'* ]]
}

@test "the config never hands resurrect a path to expand" {
    # The shape that caused it, and the one a future edit would reach for: a
    # literal value written in the file. It only has to be mishandled by one of
    # the two passes it then goes through.
    ! grep -Eq "^[[:space:]]*set(-option)? .*@resurrect-dir" "$(TMUX_CONF)"
}

@test "a domain machine is keyed by its short name, like every other envup file" {
    # $HOSTNAME is the FQDN on a domain-joined box, while $ENVUP_HOST — which
    # decides whose hosts/<name>.conf gets linked to ~/.tmux/host.conf — is the
    # short name. One machine under two names is how the save directory ends up
    # somewhere nothing else in envup agrees with.
    command -v tmux >/dev/null 2>&1 || skip "tmux not installed"
    local dir; dir="$(conf_resurrect_dir box.corp.example.com)" ||
        skip "cannot start a tmux server here"
    [[ "$dir" == */box ]]
    grep -q 'ENVUP_HOST%%\.\*' "$REPO_ROOT/lib/caps.sh"
}

@test "with no hostname to be had the plugin's own default is left alone" {
    # An unkeyed directory shared between machines costs you the split; a real
    # directory named "" costs you the saves. Prefer the first.
    command -v tmux >/dev/null 2>&1 || skip "tmux not installed"
    local dir; dir="$(conf_resurrect_dir '')" || skip "cannot start a tmux server here"
    [ -z "$dir" ]
}

@test "an unplanned reboot costs at most five minutes of layout" {
    grep -q "@continuum-save-interval '5'" "$(TMUX_CONF)"
    grep -q "@continuum-restore 'on'"      "$(TMUX_CONF)"
}

# ---- nothing starts tmux behind your back --------------------------------

@test "no zsh slice starts a tmux server" {
    # An auto-attach at login was tried and dropped: deciding for you whether
    # *this* connection wants a multiplexer means sometimes deciding wrong, and
    # a wrong guess drops you into a session that is not the one you left —
    # which reads as "the restore is broken", not as "the guess was bad".
    # Attaching is now something you type. This is the guard against it coming
    # back by accident.
    local d="$REPO_ROOT/modules/zsh/files/.zshrc.d"
    ! grep -rlE '^[^#]*tmux (attach|new-session|start-server)' "$d"/*.zsh
}

@test "the resume helper is linked, so the short name in 65-func.zsh resolves" {
    grep -q 'modules/tmux/files/bin/tmux-resume:\$HOME/.local/bin/tmux-resume' \
        "$REPO_ROOT/modules/tmux/meta.sh"
    [ -x "$(RESUME)" ]
    # Defined only if the name is free, like `ts` — shadowing someone else's
    # binary from a dotfiles repo is how you lose an afternoon.
    grep -q 'command -v tm >/dev/null' \
        "$REPO_ROOT/modules/zsh/files/.zshrc.d/65-func.zsh"
}

# ---- what `tmux-resume` does ----------------------------------------------

@test "an existing server is joined, not restarted" {
    echo 0 > "$TMUX_SESSIONS"        # a session is already there
    resume
    ! grep -q 'start-server' "$TMUX_CALLS"
    grep -q 'tmux attach' "$TMUX_CALLS"
}

@test "with nothing saved it does not sit waiting for a restore that will not come" {
    # continuum only restores when there is a save file. A first run must not
    # pay the timeout to find that out.
    local t0 t1
    t0="$(date +%s)"
    resume
    t1="$(date +%s)"
    grep -q 'new-session -s main' "$TMUX_CALLS"
    [ "$(( t1 - t0 ))" -lt 3 ]
}

@test "it waits for continuum's restore instead of racing it into an empty session" {
    # This is the whole reason the command exists. continuum restores
    # asynchronously — it sleeps a second first so tmux can finish sourcing its
    # plugins — so plain `tmux` creates its own session in that gap and leaves
    # you staring at an empty shell with the real work restored behind it.
    saved_layout
    echo 3 > "$TMUX_SESSIONS"        # the restore lands on the third check
    resume
    grep -q 'start-server' "$TMUX_CALLS"
    ! grep -q 'new-session' "$TMUX_CALLS"
    grep -q 'tmux attach' "$TMUX_CALLS"
}

@test "a restore that never arrives still gets you a shell" {
    saved_layout
    resume                            # has-session never succeeds
    grep -q 'new-session -s main' "$TMUX_CALLS"
}

@test "the session it falls back to can be named" {
    ENVUP_TMUX_SESSION=work resume
    grep -q 'new-session -s work' "$TMUX_CALLS"
}

@test "run from inside tmux it refuses instead of nesting" {
    TMUX="/tmp/fake,1,0" resume
    [ "$status" -ne 0 ]
    [[ "$output" == *"already inside tmux"* ]]
    [ ! -s "$TMUX_CALLS" ]
}

@test "on a machine without tmux it says so instead of failing obscurely" {
    rm -f "$STUB_BIN/tmux"
    isolate_path
    resume
    [ "$status" -ne 0 ]
    [[ "$output" == *"tmux is not installed"* ]]
}

@test "--help explains itself without touching the machine" {
    resume --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: tmux-resume"* ]]
    [ ! -s "$TMUX_CALLS" ]
}

@test "a mistyped argument is refused, not ignored" {
    resume --attach
    [ "$status" -ne 0 ]
    [ ! -s "$TMUX_CALLS" ]
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
