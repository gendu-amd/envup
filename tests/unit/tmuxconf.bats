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
