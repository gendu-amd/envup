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

# ---- the clipboard ---------------------------------------------------------
#
# Copy is the one thing here that fails without saying anything: the text goes
# into tmux's buffer either way, and whether it reaches the system clipboard
# depends on a terminal setting on a machine this config never sees. So the
# probe is run rather than read.

# The shell command out of the multi-line `run-shell '<this>'` block that picks
# the clipboard tool. Anchored on a line that is nothing but the opening quote
# and a continuation, which the one-line run-shells above cannot match.
conf_copy_probe() {
    sed -n "/^run-shell '[[:space:]]*.\$/,/^    fi'\$/p" "$(TMUX_CONF)" |
        sed "1s/^run-shell '//; \$s/'\$//"
}

# A tmux that answers -V with $1 and otherwise echoes the command it was given,
# so a test can assert on what the probe asked tmux to do.
stub_tmux_version() {
    stub_bin tmux <<EOF
#!/bin/bash
[[ "\$1" == -V ]] && { echo "tmux $1"; exit 0; }
printf '%s\n' "\$*"
EOF
}

@test "the clipboard tool is probed, not assumed" {
    local cmd; cmd="$(conf_copy_probe)"
    [ -n "$cmd" ]
}

@test "a machine with pbcopy pipes copies to it instead of out as OSC 52" {
    # The bug this exists for: on a Mac running tmux locally, copy went out as
    # an escape sequence that iTerm2 drops unless you have turned it on and
    # Terminal.app drops always, while pbcopy sat unused on PATH.
    stub_tmux_version 3.4
    stub_bin pbcopy <<'EOF'
#!/bin/sh
EOF
    isolate_path
    DISPLAY= run sh -c "$(conf_copy_probe)"
    [ "$status" -eq 0 ]
    [[ "$output" == *"copy-pipe-and-cancel pbcopy"* ]]
    [[ "$output" == *"MouseDragEnd1Pane send -X copy-pipe-no-clear pbcopy"* ]]
}

@test "a machine with no clipboard tool is left on the OSC 52 route" {
    # A server you ssh to. Nothing to pipe into, so the static copy-selection
    # bindings above stand and set-clipboard carries the text to your terminal.
    stub_tmux_version 3.4
    isolate_path
    DISPLAY= run sh -c "$(conf_copy_probe)"
    [[ "$output" != *copy-pipe* ]]
    [[ "$output" == *"MouseDragEnd1Pane send -X copy-selection-no-clear"* ]]
}

@test "xclip without a DISPLAY is not a clipboard" {
    # Same rule as nvim's clipboard.lua: presence on PATH is not enough. Piping
    # into xclip on a headless box copies nothing and prints an error into the
    # pane.
    stub_tmux_version 3.4
    stub_bin xclip <<'EOF'
#!/bin/sh
EOF
    isolate_path
    DISPLAY= run sh -c "$(conf_copy_probe)"
    [[ "$output" != *copy-pipe* ]]
    [[ "$output" != *xclip* ]]
}

@test "an X11 machine with a DISPLAY does get xclip, as one argument" {
    # The command is multi-word, and tmux takes it as a single argv element.
    # Unquoted it would arrive as three and the binding would be nonsense.
    stub_tmux_version 3.4
    stub_bin xclip <<'EOF'
#!/bin/sh
EOF
    isolate_path
    DISPLAY=:0 run sh -c "$(conf_copy_probe)"
    [[ "$output" == *"copy-pipe-and-cancel xclip -selection clipboard"* ]]
}

@test "tmux before 3.0 is not handed a command it does not have" {
    # copy-pipe-no-clear arrived in 3.0. tmux does not check the -X argument
    # when the key is *bound* — `bind` succeeds on 2.x and the key is then dead
    # when pressed — so this cannot be attempted and caught, only decided.
    stub_tmux_version 2.7
    stub_bin pbcopy <<'EOF'
#!/bin/sh
EOF
    isolate_path
    DISPLAY= run sh -c "$(conf_copy_probe)"
    [[ "$output" == *"MouseDragEnd1Pane send -X copy-pipe pbcopy"* ]]
    [[ "$output" != *no-clear* ]]
}

@test "a two-digit major version is not read as older than 3" {
    stub_tmux_version 10.1
    stub_bin pbcopy <<'EOF'
#!/bin/sh
EOF
    isolate_path
    DISPLAY= run sh -c "$(conf_copy_probe)"
    [[ "$output" == *copy-pipe-no-clear* ]]
}

@test "no -no-clear command is bound unconditionally" {
    # The regression: the file used to bind copy-selection-no-clear outright,
    # which is silently dead on every tmux older than 3.0. Anything version
    # dependent has to come from the probe, not from a static line.
    ! grep -Eq '^bind .*no-clear' "$(TMUX_CONF)"
}
