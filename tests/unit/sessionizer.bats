#!/usr/bin/env bats
# tmux-sessionizer: pick a project, land in a session named after it.
#
# It runs from a tmux key binding, which means two things the tests have to
# respect: it never sees your shell environment, and when it goes wrong there is
# nowhere for the error to go. So the interesting cases are all failure cases —
# no roots, no fzf, cancelled picker, a name tmux cannot use.

load '../test_helper'

setup() {
    common_setup
    SZ="$REPO_ROOT/modules/tmux/files/bin/tmux-sessionizer"
    # tmux must exist for the script to get past its own guard; a stub keeps the
    # test off the real tmux server and lets us see what it was asked to do.
    stub_bin tmux <<'EOF'
#!/bin/bash
printf 'tmux %s\n' "$*" >> "$TMUX_CALLS"
# has-session: only 'existing' is already there.
if [[ "$1" == has-session ]]; then
    [[ "$2" == "=existing" ]] && exit 0
    exit 1
fi
exit 0
EOF
    export TMUX_CALLS="$TEST_TMP/tmux-calls"
    : > "$TMUX_CALLS"
    # The tests decide whether we are "inside tmux"; the machine running them
    # does not get a vote.
    unset TMUX
}
teardown() { common_teardown; }

# fzf that picks the Nth line it is offered (1-based) and records the menu.
stub_fzf_pick() {
    export FZF_PICK="$1" FZF_MENU="$TEST_TMP/fzf-menu"
    stub_bin fzf <<'EOF'
#!/bin/bash
cat > "$FZF_MENU"
[[ "$FZF_PICK" == "cancel" ]] && exit 130
sed -n "${FZF_PICK}p" "$FZF_MENU"
EOF
}

@test "it is executable, or the tmux binding does nothing" {
    [ -x "$REPO_ROOT/modules/tmux/files/bin/tmux-sessionizer" ]
}

@test "a directory given directly skips the picker" {
    mkdir -p "$TEST_TMP/p/thing"
    run "$SZ" "$TEST_TMP/p/thing"
    [ "$status" -eq 0 ]
    grep -q 'new-session -d -s thing' "$TMUX_CALLS"
}

@test "a path that is not a directory is refused, not guessed at" {
    touch "$TEST_TMP/afile"
    run "$SZ" "$TEST_TMP/afile"
    [ "$status" -ne 0 ]
    [[ "$output" == *"not a directory"* ]]
}

@test "the roots are globs, and only directories come back" {
    mkdir -p "$TEST_TMP/w/alpha" "$TEST_TMP/w/beta"
    touch "$TEST_TMP/w/README"
    stub_fzf_pick 1
    ENVUP_PROJECT_DIRS="$TEST_TMP/w/*" run "$SZ"
    [ "$status" -eq 0 ]
    grep -q 'alpha' "$TEST_TMP/fzf-menu"
    grep -q 'beta'  "$TEST_TMP/fzf-menu"
    ! grep -q 'README' "$TEST_TMP/fzf-menu"
}

@test "a root that does not exist is not an error" {
    # Every machine is missing most of the default roots. If an unmatched glob
    # were fatal the script would fail on a first run, everywhere.
    mkdir -p "$TEST_TMP/w/alpha"
    stub_fzf_pick 1
    ENVUP_PROJECT_DIRS="$TEST_TMP/nope/*:$TEST_TMP/w/*" run "$SZ"
    [ "$status" -eq 0 ]
    grep -q 'alpha' "$TEST_TMP/fzf-menu"
}

@test "a project reachable through two roots is offered once" {
    mkdir -p "$TEST_TMP/w/alpha"
    stub_fzf_pick 1
    ENVUP_PROJECT_DIRS="$TEST_TMP/w/*:$TEST_TMP/w/*" run "$SZ"
    [ "$(grep -c 'alpha' "$TEST_TMP/fzf-menu")" -eq 1 ]
}

@test "the config file is read when no variable is set" {
    # This is the path the tmux binding actually takes: a key binding runs under
    # the tmux server's environment, which never sourced anyone's .zshrc.
    mkdir -p "$TEST_TMP/w/gamma" "$HOME/.config/envup"
    printf '# where my code lives\n%s/w/*\n\n' "$TEST_TMP" > "$HOME/.config/envup/project-dirs"
    stub_fzf_pick 1
    run env -u ENVUP_PROJECT_DIRS "$SZ"
    [ "$status" -eq 0 ]
    grep -q 'gamma' "$TEST_TMP/fzf-menu"
}

@test "cancelling the picker is not a failure" {
    mkdir -p "$TEST_TMP/w/alpha"
    stub_fzf_pick cancel
    ENVUP_PROJECT_DIRS="$TEST_TMP/w/*" run "$SZ"
    [ "$status" -eq 0 ]
    [ ! -s "$TMUX_CALLS" ]      # nothing was created
}

@test "no projects anywhere says where to list them" {
    stub_fzf_pick 1
    ENVUP_PROJECT_DIRS="$TEST_TMP/empty/*" run "$SZ"
    [ "$status" -ne 0 ]
    [[ "$output" == *"project-dirs"* ]]
}

@test "a missing fzf names itself and how to get it" {
    mkdir -p "$TEST_TMP/w/alpha"
    isolate_path tmux           # tmux stays, fzf goes
    ENVUP_PROJECT_DIRS="$TEST_TMP/w/*" run "$SZ"
    [ "$status" -ne 0 ]
    [[ "$output" == *"fzf"* ]]
}

@test "dots and colons in a project name are replaced" {
    # tmux reads both as address separators, so 'v1.2' becomes an unusable
    # session that later -t lookups cannot address.
    mkdir -p "$TEST_TMP/p/v1.2"
    run "$SZ" "$TEST_TMP/p/v1.2"
    [ "$status" -eq 0 ]
    grep -q 'new-session -d -s v1_2' "$TMUX_CALLS"
}

@test "an existing session is joined, not duplicated" {
    mkdir -p "$TEST_TMP/p/existing"
    run "$SZ" "$TEST_TMP/p/existing"
    [ "$status" -eq 0 ]
    ! grep -q 'new-session' "$TMUX_CALLS"
    grep -q 'attach-session -t =existing' "$TMUX_CALLS"
}

@test "the session lookup is exact" {
    # Without '=', has-session -t api also matches 'api-gateway' and you are
    # silently dropped into the wrong project.
    mkdir -p "$TEST_TMP/p/thing"
    run "$SZ" "$TEST_TMP/p/thing"
    grep -q 'has-session -t =thing' "$TMUX_CALLS"
}

@test "inside tmux it switches; outside it attaches" {
    mkdir -p "$TEST_TMP/p/existing"

    TMUX="/tmp/fake,1,0" run "$SZ" "$TEST_TMP/p/existing"
    grep -q 'switch-client -t =existing' "$TMUX_CALLS"

    : > "$TMUX_CALLS"
    run env -u TMUX "$SZ" "$TEST_TMP/p/existing"
    grep -q 'attach-session -t =existing' "$TMUX_CALLS"
}

@test "a trailing slash does not become an empty session name" {
    mkdir -p "$TEST_TMP/p/thing"
    run "$SZ" "$TEST_TMP/p/thing/"
    [ "$status" -eq 0 ]
    grep -q 'new-session -d -s thing' "$TMUX_CALLS"
}

@test "no tmux at all is reported, not left as a bare command-not-found" {
    rm -f "$STUB_BIN/tmux"
    isolate_path                # a known-good minimum, and tmux is not in it
    run "$SZ" "$TEST_TMP"
    [ "$status" -ne 0 ]
    [[ "$output" == *"tmux"* ]]
}

# ---- how it is reached ---------------------------------------------------

@test "an error from the key binding stays on screen long enough to read" {
    # tmux closes the throwaway window the moment the command exits, so without
    # the pause `prefix f` on a machine with no fzf is a key that does nothing.
    mkdir -p "$TEST_TMP/w/alpha"
    isolate_path tmux
    ENVUP_TS_PAUSE=1 ENVUP_PROJECT_DIRS="$TEST_TMP/w/*" run "$SZ" </dev/null
    [ "$status" -ne 0 ]
    [[ "$output" == *"fzf"* ]]
    # /dev/tty is unreadable under `run`, which is the same situation as a
    # non-interactive caller: say the piece, do not hang waiting for a key.
}

@test "the shell shortcut does not pause — there is no window to lose" {
    mkdir -p "$TEST_TMP/w/alpha"
    isolate_path tmux
    ENVUP_PROJECT_DIRS="$TEST_TMP/w/*" run "$SZ"
    [[ "$output" != *"press Enter"* ]]
}

@test "tmux binds it, and envup links it onto PATH" {
    grep -q "bind f new-window -n sessionizer 'ENVUP_TS_PAUSE=1 ~/.local/bin/tmux-sessionizer'" \
        "$REPO_ROOT/modules/tmux/files/.tmux.conf"
    grep -q 'modules/tmux/files/bin/tmux-sessionizer:\$HOME/.local/bin/tmux-sessionizer' \
        "$REPO_ROOT/modules/tmux/meta.sh"
}

@test "the ts shortcut refuses to shadow another ts" {
    # moreutils ships one. Silently replacing someone's binary with ours is how
    # you lose an afternoon.
    local f="$REPO_ROOT/modules/zsh/files/.zshrc.d/65-func.zsh"
    grep -q '! command -v ts >/dev/null 2>&1' "$f"
}
