#!/usr/bin/env bats
# I3, the parts that are not symlinks.
#
# unlink.bats covers "uninstall removes envup's own links and nothing else".
# The gap this file closes is everything envup creates that is *not* a link:
# the directories it makes to hold a link, and the rc file it has to create
# before it can write a managed block into it. Both used to survive uninstall —
# a real install left ~/.bashrc at 0 bytes and three empty directories behind,
# which is a promise of reversibility with an asterisk on it.
#
# Both halves are two-sided, and the second side is the one worth guarding:
#   - a directory goes only if it is *empty*
#   - a file goes only if envup *created* it and it is empty *again*
# Getting either wrong deletes something the user owns.

load '../test_helper'

setup() { common_setup; }
teardown() { common_teardown; }

# ---- dir_prune_empty ------------------------------------------------------

@test "dir_prune_empty: removes an empty directory" {
    mkdir -p "$HOME/.config/git"
    run dir_prune_empty "$HOME/.config/git"
    [ "$status" -eq 0 ]
    [ ! -d "$HOME/.config/git" ]
}

@test "dir_prune_empty: walks up through parents that are now empty too" {
    mkdir -p "$HOME/.tmux/plugins"
    dir_prune_empty "$HOME/.tmux/plugins"
    [ ! -d "$HOME/.tmux/plugins" ]
    [ ! -d "$HOME/.tmux" ]
}

@test "dir_prune_empty: stops at the first parent that still has something in it" {
    mkdir -p "$HOME/.config/git"
    echo x > "$HOME/.config/keep"
    dir_prune_empty "$HOME/.config/git"
    [ ! -d "$HOME/.config/git" ]
    [ -d "$HOME/.config" ]
    [ -f "$HOME/.config/keep" ]
}

@test "dir_prune_empty: leaves a directory with a file in it (rmdir is the guard)" {
    mkdir -p "$HOME/.local/bin"
    echo binary > "$HOME/.local/bin/eza"
    run dir_prune_empty "$HOME/.local/bin"
    [ "$status" -eq 0 ]
    [ -f "$HOME/.local/bin/eza" ]
}

@test "dir_prune_empty: a dotfile still counts as contents" {
    mkdir -p "$HOME/.tmux/plugins"
    : > "$HOME/.tmux/plugins/.gitkeep"
    dir_prune_empty "$HOME/.tmux/plugins"
    [ -d "$HOME/.tmux/plugins" ]
}

@test "dir_prune_empty: an empty dir containing an empty dir is taken in one call" {
    mkdir -p "$HOME/a/b"
    dir_prune_empty "$HOME/a/b"
    [ ! -d "$HOME/a" ]
}

@test "dir_prune_empty: never climbs past \$HOME even when everything is empty" {
    # $HOME here is a subdirectory of TEST_TMP, so a runaway loop would be
    # visible as the sandbox itself disappearing.
    mkdir -p "$HOME/x"
    dir_prune_empty "$HOME/x"
    [ -d "$HOME" ]
    [ -d "$TEST_TMP" ]
}

@test "dir_prune_empty: refuses a directory outside \$HOME" {
    mkdir -p "$TEST_TMP/elsewhere"
    dir_prune_empty "$TEST_TMP/elsewhere"
    [ -d "$TEST_TMP/elsewhere" ]
}

@test "dir_prune_empty: no argument, missing directory and \$HOME itself are all no-ops" {
    run dir_prune_empty "";              [ "$status" -eq 0 ]
    run dir_prune_empty "$HOME/nope";    [ "$status" -eq 0 ]
    run dir_prune_empty "$HOME";         [ "$status" -eq 0 ]
    [ -d "$HOME" ]
}

@test "dir_prune_empty: dry-run removes nothing (I4)" {
    mkdir -p "$HOME/.config/git"
    ENVUP_DRY_RUN=1 run dir_prune_empty "$HOME/.config/git"
    [ "$status" -eq 0 ]
    [ -d "$HOME/.config/git" ]
}

# ---- unlink_safe reclaims the directory it linked into --------------------

@test "unlink_safe: takes back the directory that only existed to hold the link" {
    mkdir -p "$ENVUP_HOME/files"
    echo repo > "$ENVUP_HOME/files/ignore"
    safe_link "files/ignore" "$HOME/.config/git/ignore"
    [ -L "$HOME/.config/git/ignore" ]

    unlink_safe "$HOME/.config/git/ignore"
    [ ! -e "$HOME/.config/git/ignore" ]
    [ ! -d "$HOME/.config/git" ]
}

@test "unlink_safe: leaves the directory when the user has other things in it" {
    mkdir -p "$ENVUP_HOME/files"
    echo repo > "$ENVUP_HOME/files/ignore"
    safe_link "files/ignore" "$HOME/.config/git/ignore"
    echo mine > "$HOME/.config/git/attributes"

    unlink_safe "$HOME/.config/git/ignore"
    [ -f "$HOME/.config/git/attributes" ]
}

@test "unlink_safe: refusing to unlink also means not touching the directory" {
    mkdir -p "$HOME/.config/git"
    echo user-data > "$HOME/.config/git/ignore"
    unlink_safe "$HOME/.config/git/ignore"
    [ -f "$HOME/.config/git/ignore" ]
    [ -d "$HOME/.config/git" ]
}

@test "unlink_safe: a link straight in \$HOME does not endanger \$HOME" {
    mkdir -p "$ENVUP_HOME/files"
    echo repo > "$ENVUP_HOME/files/zshrc"
    safe_link "files/zshrc" "$HOME/.zshrc"
    unlink_safe "$HOME/.zshrc"
    [ ! -e "$HOME/.zshrc" ]
    [ -d "$HOME" ]
}

# ---- the created-file ledger ----------------------------------------------

@test "block_set: creating the file records it; block_del takes it back" {
    [ ! -e "$HOME/.bashrc" ]
    echo 'exec zsh' | block_set "$HOME/.bashrc" zsh-default
    [ -s "$HOME/.bashrc" ]
    grep -qF 'exec zsh' "$HOME/.bashrc"

    block_del "$HOME/.bashrc" zsh-default
    [ ! -e "$HOME/.bashrc" ]
}

@test "block_del: a file the user already had is never reclaimed, even empty" {
    : > "$HOME/.bashrc"                       # the user's own, and empty
    echo 'exec zsh' | block_set "$HOME/.bashrc" zsh-default
    block_del "$HOME/.bashrc" zsh-default
    [ -f "$HOME/.bashrc" ]
    [ ! -s "$HOME/.bashrc" ]
}

@test "block_del: a file envup created but the user has since written to stays" {
    echo 'exec zsh' | block_set "$HOME/.bashrc" zsh-default
    echo 'export PS1="> "' >> "$HOME/.bashrc"
    block_del "$HOME/.bashrc" zsh-default
    [ -s "$HOME/.bashrc" ]
    grep -qF 'export PS1' "$HOME/.bashrc"
    ! grep -qF 'exec zsh' "$HOME/.bashrc"
}

@test "block_set: replacing an existing block does not delete the file mid-write" {
    # block_set calls block_del internally. If the reclaim ran there, the second
    # call would remove the file it had just touched and write into a new one —
    # or, on the first call, delete the freshly created empty file.
    echo 'v1' | block_set "$HOME/.bashrc" zsh-default
    echo 'v2' | block_set "$HOME/.bashrc" zsh-default
    [ -s "$HOME/.bashrc" ]
    grep -qF 'v2' "$HOME/.bashrc"
    [ "$(grep -c 'envup:zsh-default' "$HOME/.bashrc")" -eq 2 ]   # one begin, one end
}

@test "created_reclaim: forgets the file after acting, so a later empty file is safe" {
    echo 'exec zsh' | block_set "$HOME/.bashrc" zsh-default
    block_del "$HOME/.bashrc" zsh-default
    [ ! -e "$HOME/.bashrc" ]

    : > "$HOME/.bashrc"                       # a different file, same name
    run created_reclaim "$HOME/.bashrc"
    [ "$status" -eq 0 ]
    [ -f "$HOME/.bashrc" ]
}

@test "created_reclaim: a symlink is never deleted, whatever the ledger says" {
    # touch follows a symlink, so block_set would have written to the target.
    echo repo > "$TEST_TMP/target"
    ln -s "$TEST_TMP/target" "$HOME/.bashrc"
    created_note "$HOME/.bashrc"
    : > "$TEST_TMP/target"
    created_reclaim "$HOME/.bashrc"
    [ -L "$HOME/.bashrc" ]
}

@test "created_reclaim: nothing recorded, nothing happens" {
    : > "$HOME/.bashrc"
    run created_reclaim "$HOME/.bashrc"
    [ "$status" -eq 0 ]
    [ -f "$HOME/.bashrc" ]
}

@test "created_note: dry-run writes no ledger, and reclaim deletes nothing (I4)" {
    ENVUP_DRY_RUN=1 created_note "$HOME/.bashrc"
    [ ! -e "$ENVUP_STATE_DIR/created" ]

    created_note "$HOME/.bashrc"; : > "$HOME/.bashrc"
    ENVUP_DRY_RUN=1 created_reclaim "$HOME/.bashrc"
    [ -f "$HOME/.bashrc" ]
}

@test "created_reclaim: the ledger itself goes once it is empty" {
    echo 'exec zsh' | block_set "$HOME/.bashrc" zsh-default
    [ -s "$ENVUP_STATE_DIR/created" ]
    block_del "$HOME/.bashrc" zsh-default
    [ ! -e "$ENVUP_STATE_DIR/created" ]
}

@test "created_reclaim: a ledger with other files in it survives" {
    created_note "$HOME/.profile"
    echo 'exec zsh' | block_set "$HOME/.bashrc" zsh-default
    block_del "$HOME/.bashrc" zsh-default
    [ -s "$ENVUP_STATE_DIR/created" ]
    grep -qxF "$HOME/.profile" "$ENVUP_STATE_DIR/created"
}

@test "created_note: recording the same file twice keeps one line" {
    created_note "$HOME/.bashrc"
    created_note "$HOME/.bashrc"
    [ "$(wc -l < "$ENVUP_STATE_DIR/created")" -eq 1 ]
}

@test "the ledger lives with the manifest, not in the repo" {
    # Two machines share the repo over NFS; what exists on one of them is not a
    # fact about the other.
    created_note "$HOME/.bashrc"
    [ -f "$ENVUP_STATE_DIR/created" ]
    [ ! -e "$ENVUP_HOME/created" ]
}

# ---- ~/.local/bin ---------------------------------------------------------

@test "engine_uninstall: an empty ~/.local/bin does not outlive the module" {
    mk_module solo
    mkdir -p "$ENVUP_LOCAL_BIN"
    run engine_uninstall solo
    [ "$status" -eq 0 ]
    [ ! -d "$ENVUP_LOCAL_BIN" ]
}

@test "engine_uninstall: a ~/.local/bin with a binary in it is left alone" {
    mk_module solo
    mkdir -p "$ENVUP_LOCAL_BIN"
    echo '#!/bin/sh' > "$ENVUP_LOCAL_BIN/zoxide"; chmod +x "$ENVUP_LOCAL_BIN/zoxide"
    engine_uninstall solo
    [ -x "$ENVUP_LOCAL_BIN/zoxide" ]
}
