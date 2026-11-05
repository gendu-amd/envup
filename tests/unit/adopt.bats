#!/usr/bin/env bats
# `envup adopt` (lib/adopt.sh): get a third-party installer's appended lines out
# of the tracked repo and into machine-local config.
#
# The real case this was written for: nvm's install script appended five lines
# to modules/zsh/files/.zshrc — a *tracked* file, reachable because ~/.zshrc is
# a symlink into the repo. The next `envup upgrade` on a different machine then
# failed its git pull.

load '../test_helper'

setup() {
    common_setup
    git -C "$ENVUP_HOME" init -q
    git -C "$ENVUP_HOME" config user.email t@example.com
    git -C "$ENVUP_HOME" config user.name  t
    mkdir -p "$ENVUP_HOME/modules/zsh/files"
    ZRC="$ENVUP_HOME/modules/zsh/files/.zshrc"
    printf 'source ~/.zshrc.d/00-guard.zsh\nsource ~/.zshrc.d/10-path.zsh\n' > "$ZRC"
    git -C "$ENVUP_HOME" add -A
    git -C "$ENVUP_HOME" commit -qm init
}
teardown() { common_teardown; }

pollute() { printf '\nexport NVM_DIR="$HOME/.nvm"\n[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"\n' >> "$ZRC"; }

# ---- detection -----------------------------------------------------------

@test "adopt_appended: reports the appended text of a polluted file" {
    pollute
    run adopt_appended modules/zsh/files/.zshrc
    [ "$status" -eq 0 ]
    [[ "$output" == *"NVM_DIR"* ]]
    [[ "$output" != *"00-guard"* ]]   # only what was added, not the whole file
}

@test "adopt_appended: a clean file has nothing appended" {
    run adopt_appended modules/zsh/files/.zshrc
    [ "$status" -ne 0 ]
}

@test "adopt_appended: an edit in the middle is not an append" {
    # The signature adopt keys on is "everything committed is still there,
    # verbatim, with new lines after it". Anything else needs a human.
    printf 'CHANGED\nsource ~/.zshrc.d/10-path.zsh\nextra\n' > "$ZRC"
    run adopt_appended modules/zsh/files/.zshrc
    [ "$status" -ne 0 ]
}

@test "adopt_appended: deleting the tail is not an append" {
    printf 'source ~/.zshrc.d/00-guard.zsh\n' > "$ZRC"
    run adopt_appended modules/zsh/files/.zshrc
    [ "$status" -ne 0 ]
}

@test "adopt_appended: an untracked file is not an append" {
    printf 'x\n' > "$ENVUP_HOME/modules/zsh/files/brand-new.zsh"
    run adopt_appended modules/zsh/files/brand-new.zsh
    [ "$status" -ne 0 ]
}

# ---- the command ---------------------------------------------------------

@test "adopt: moves the appended lines to ~/.zshrc.local and restores the file" {
    pollute
    run adopt_main
    [ "$status" -eq 0 ]

    # The repo file is byte-identical to the commit again…
    run git -C "$ENVUP_HOME" status --porcelain -- 'modules/*/files/*'
    [ -z "$output" ]
    # …and the lines are not lost, they are in the file 80-local.zsh sources.
    run cat "$HOME/.zshrc.local"
    [[ "$output" == *"NVM_DIR"* ]]
    [[ "$output" == *"adopted by envup"* ]]
}

@test "adopt: appends to an existing ~/.zshrc.local rather than replacing it" {
    echo "# my own settings" > "$HOME/.zshrc.local"
    pollute
    adopt_main
    run cat "$HOME/.zshrc.local"
    [[ "$output" == *"my own settings"* ]]
    [[ "$output" == *"NVM_DIR"* ]]
}

@test "adopt -n: changes nothing" {
    pollute
    run adopt_main -n
    [ "$status" -eq 0 ]
    [[ "$output" == *"dry-run"* ]]
    [ ! -e "$HOME/.zshrc.local" ]
    run grep -c NVM_DIR "$ZRC"
    [ "$output" -ge 1 ]
}

@test "adopt: leaves a hand-edited file alone and says why" {
    printf 'CHANGED\nsource ~/.zshrc.d/10-path.zsh\n' > "$ZRC"
    run adopt_main
    [ "$status" -eq 0 ]
    [[ "$output" == *"not a plain append"* ]]
    run grep -c CHANGED "$ZRC"
    [ "$output" = "1" ]
}

@test "adopt: a clean repo is a success, not an error" {
    run adopt_main
    [ "$status" -eq 0 ]
    [[ "$output" == *"no drift"* ]]
}

@test "adopt PATH: restricts the operation to the named file" {
    mkdir -p "$ENVUP_HOME/modules/tmux/files"
    printf 'set -g mouse on\n' > "$ENVUP_HOME/modules/tmux/files/.tmux.conf"
    git -C "$ENVUP_HOME" add -A
    git -C "$ENVUP_HOME" commit -qm tmux
    pollute
    printf 'set -g status off\n' >> "$ENVUP_HOME/modules/tmux/files/.tmux.conf"

    run adopt_main modules/zsh/files/.zshrc
    [ "$status" -eq 0 ]
    run grep -c 'status off' "$ENVUP_HOME/modules/tmux/files/.tmux.conf"
    [ "$output" = "1" ]
    run grep -c NVM_DIR "$ZRC"
    [ "$output" = "0" ]
}

@test "adopt: a non-zsh managed file is parked in the state dir, not guessed at" {
    mkdir -p "$ENVUP_HOME/modules/tmux/files"
    printf 'set -g mouse on\n' > "$ENVUP_HOME/modules/tmux/files/.tmux.conf"
    git -C "$ENVUP_HOME" add -A
    git -C "$ENVUP_HOME" commit -qm tmux
    printf 'set -g status off\n' >> "$ENVUP_HOME/modules/tmux/files/.tmux.conf"

    run adopt_main
    [ "$status" -eq 0 ]
    [[ "$output" == *"$ENVUP_STATE_DIR/adopted/"* ]]
    run bash -c "cat '$ENVUP_STATE_DIR'/adopted/*/*"
    [[ "$output" == *"status off"* ]]
}

@test "doctor: names adopt when a managed file has lines appended to it" {
    pollute
    run doctor_main
    [[ "$output" == *"envup adopt"* ]]
    # Drift is a note, not an issue: uncommitted work in your own dotfiles is
    # normal, and doctor failing over it would train people to ignore doctor.
    [ "$status" -eq 0 ]
}
