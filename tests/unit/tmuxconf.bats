#!/usr/bin/env bats
# .tmux.conf, the parts that have to hold on a machine we have never seen.
#
# tmux reads its config once, at server start, and a line that is wrong for this
# box does not fail — it quietly leaves you with the wrong colours or a dead
# Home key, and you blame the terminal. So the conditional bits are extracted
# from the file and run, rather than eyeballed.

load '../test_helper'

setup() { common_setup; }
teardown() { common_teardown; }

TMUX_CONF() { printf '%s' "$REPO_ROOT/modules/tmux/files/.tmux.conf"; }

# The shell condition out of `if-shell '<this>' ...`, by the tool it probes.
conf_condition() {
    sed -n "/^if-shell '$1/s/^if-shell '\([^']*\)'.*/\1/p" "$(TMUX_CONF)"
}

# ---- default-terminal ----------------------------------------------------

@test "the terminfo entry is probed, not assumed" {
    local cond; cond="$(conf_condition infocmp)"
    [ -n "$cond" ]
}

@test "an ncurses that knows tmux-256color gets tmux-256color" {
    stub_bin infocmp <<'EOF'
#!/bin/bash
[[ "$1" == tmux-256color ]] && exit 0
exit 1
EOF
    run sh -c "$(conf_condition infocmp)"
    [ "$status" -eq 0 ]
    grep -q "'set -g default-terminal \"tmux-256color\"'" "$(TMUX_CONF)"
}

@test "an ncurses that does not falls back to screen-256color" {
    # ncurses added the tmux-256color entry in 6.0. CentOS 7 shipped 5.9, and
    # naming an entry that is not installed costs you the arrow keys.
    stub_bin infocmp <<'EOF'
#!/bin/bash
exit 1
EOF
    run sh -c "$(conf_condition infocmp)"
    [ "$status" -ne 0 ]
    grep -q "'set -g default-terminal \"screen-256color\"'" "$(TMUX_CONF)"
}

@test "no infocmp at all is answered silently" {
    # Slim images drop ncurses-bin. Without the redirect this is a
    # 'command not found' printed over the first thing you see in tmux.
    rm -f "$STUB_BIN/infocmp"
    isolate_path
    run sh -c "$(conf_condition infocmp)"
    [ "$status" -ne 0 ]
    [ -z "$output" ]
}

@test "true colour is enabled for whichever name won" {
    # The override globs on *256col*, which is the one thing screen-256color and
    # tmux-256color have in common. Narrowing it to either name would switch
    # truecolor off on half the machines.
    grep -q 'terminal-overrides ",\*256col\*:Tc"' "$(TMUX_CONF)"
}

@test "default-terminal is never set unconditionally" {
    # A stray `set -g default-terminal` later in the file would win over the
    # probe and undo all of the above.
    ! grep -Eq '^[[:space:]]*set(-option)? .*default-terminal' "$(TMUX_CONF)"
}

# ---- default-shell -------------------------------------------------------

# The shell command out of the `run-shell '<this>'` line that picks the shell.
conf_shell_probe() {
    sed -n "/^run-shell 'command -v zsh/s/^run-shell '\(.*\)'\$/\1/p" "$(TMUX_CONF)"
}

@test "the shell is probed, not assumed" {
    local cmd; cmd="$(conf_shell_probe)"
    [ -n "$cmd" ]
}

@test "a machine with zsh gets zsh, by absolute path" {
    # tmux ignores a default-shell that is not a full path and quietly uses
    # /bin/sh instead, so passing the bare name through would give every pane a
    # posix shell on exactly the machines this line exists for.
    mkdir -p "$TEST_TMP/zbin"
    printf '#!/bin/sh\n' > "$TEST_TMP/zbin/zsh"; chmod +x "$TEST_TMP/zbin/zsh"
    stub_bin tmux <<'EOF'
#!/bin/bash
printf '%s\n' "$*"
EOF
    PATH="$TEST_TMP/zbin:$PATH" run sh -c "$(conf_shell_probe)"
    [ "$status" -eq 0 ]
    [ "$output" = "set -g default-shell $TEST_TMP/zbin/zsh" ]
}

@test "a machine without zsh is left alone" {
    # Nothing set at all, so tmux keeps starting the login shell. Pointing the
    # option at a zsh that is not there would leave the server unable to open a
    # pane, which is a worse answer than bash.
    stub_bin tmux <<'EOF'
#!/bin/bash
printf '%s\n' "$*"
EOF
    isolate_path
    run sh -c "$(conf_shell_probe)"
    [ "$status" -ne 0 ]
    [ -z "$output" ]
}

@test "the shell option is never set unconditionally, and never as a command" {
    # default-command is the one that looks like a synonym and is not: tmux runs
    # it through `sh -c`, so setting it here would silently take away the login
    # shell — no /etc/profile, no ~/.zprofile, no `module`, no conda.
    ! grep -Eq '^[[:space:]]*set(-option)? .*default-(shell|command)' "$(TMUX_CONF)"
}

# ---- the rest of the file ------------------------------------------------

@test "every way of opening somewhere to type starts in the current directory" {
    # Splits have taken -c since they were written and `c` did not, so a new
    # window opened from a session started by hand landed back in $HOME. One
    # key out of three behaving differently is the kind of thing you stop
    # noticing and start working around.
    local k line
    for k in '|' '-' 'c'; do
        line="$(grep -F "bind $k " "$(TMUX_CONF)")"
        [ -n "$line" ]
        [[ "$line" == *'-c "#{pane_current_path}"'* ]]
    done
}

@test "the scrollback limit is not quietly lower than the plugin's" {
    # tmux-sensible raises history-limit to 50000 — but only when it finds
    # tmux's default of 2000 still in place. Any number here wins over it,
    # including a smaller one, and the plugin then looks like it did nothing.
    local n
    n="$(sed -n 's/^set -g history-limit \([0-9]*\).*/\1/p' "$(TMUX_CONF)")"
    [ -n "$n" ]
    [ "$n" -ge 50000 ]
}
