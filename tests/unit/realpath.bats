#!/usr/bin/env bats
# Path identity (lib/fs.sh) — "are these two names the same file?"
#
# Every deletion envup performs and every link it decides not to rebuild rests on
# this question. It gets hard in exactly two places, and both are places envup is
# actually used: a macOS without GNU coreutils (readlink has no -f) and a home
# directory reachable by two names (NFS/autofs: /home/me -> /mnt/home/me).
# Getting it wrong is not cosmetic — `uninstall` walks away leaving its own
# symlinks behind (C4), and every install tears down links that were fine (C5).

load '../test_helper'

setup() { common_setup; }
teardown() { common_teardown; }

# ---- the three tiers -----------------------------------------------------

@test "_realpath: every available implementation gives the same answer" {
    # A path with a symlinked directory component AND a symlinked leaf, which is
    # where naive implementations diverge.
    mkdir -p "$TEST_TMP/real/sub"
    : > "$TEST_TMP/real/sub/file"
    ln -s "$TEST_TMP/real" "$TEST_TMP/alias"
    ln -s "$TEST_TMP/alias/sub/file" "$TEST_TMP/leaf"

    local want impl got
    want="$(cd "$TEST_TMP/real/sub" && pwd -P)/file"

    for impl in readlink python3 shell; do
        case "$impl" in
            readlink) readlink -f / >/dev/null 2>&1 || skip "no GNU readlink" ;;
            python3)  have python3 || skip "no python3" ;;
        esac
        got="$(_ENVUP_REALPATH_IMPL=$impl _realpath "$TEST_TMP/leaf")"
        [ "$got" = "$want" ] || { echo "$impl: got $got want $want"; false; }
    done
}

@test "_realpath: works on a path that does not exist yet" {
    # _link compares against a destination that is often absent. An empty answer
    # there would make paths_same false for two identical names.
    local got
    got="$(_realpath "$TEST_TMP/nope/not-created")"
    [ "$got" = "$TEST_TMP/nope/not-created" ]
}

@test "_realpath: a symlink loop terminates instead of hanging" {
    ln -s "$TEST_TMP/b" "$TEST_TMP/a"
    ln -s "$TEST_TMP/a" "$TEST_TMP/b"
    local t0=$SECONDS
    run _ENVUP_REALPATH_IMPL=shell _realpath "$TEST_TMP/a"
    [ $((SECONDS - t0)) -lt 10 ]
    [ -n "$output" ]
}

@test "_realpath: a relative path is made absolute" {
    mkdir -p "$TEST_TMP/rel"; : > "$TEST_TMP/rel/f"
    cd "$TEST_TMP/rel"
    run _realpath f
    [ "$output" = "$(pwd -P)/f" ]
}

# ---- ownership on a two-named home (C4) ----------------------------------
#
# Layout in every test below mirrors an autofs home:
#   $TEST_TMP/mnt/home/me/envup   the directory as the kernel resolves it
#   $TEST_TMP/nfs -> mnt/home     the name the user (and $HOME) actually uses
# NFS_HOME is that second name; don't reuse $TEST_TMP/home, which common_setup
# has already created as the sandbox $HOME (ln -s would land *inside* it).

_nfs_layout() {
    mkdir -p "$TEST_TMP/mnt/home/me/envup"
    : > "$TEST_TMP/mnt/home/me/envup/zshrc"
    ln -s "$TEST_TMP/mnt/home" "$TEST_TMP/nfs"
    NFS_HOME="$TEST_TMP/nfs"
}

@test "is_envup_link: claims a link whose target is the resolved repo path (C4)" {
    _nfs_layout
    # ENVUP_HOME as the user typed it; the link as some tool resolved it.
    ENVUP_HOME="$NFS_HOME/me/envup"
    ln -s "$TEST_TMP/mnt/home/me/envup/zshrc" "$TEST_TMP/link"
    run is_envup_link "$TEST_TMP/link"
    [ "$status" -eq 0 ]
}

@test "is_envup_link: claims a link whose target is the unresolved repo path" {
    # The mirror image: this is what envup itself writes, and it must still be
    # recognised when ENVUP_HOME arrives already resolved (e.g. from a caller
    # that ran realpath on it).
    _nfs_layout
    ENVUP_HOME="$TEST_TMP/mnt/home/me/envup"
    ln -s "$NFS_HOME/me/envup/zshrc" "$TEST_TMP/link"
    run is_envup_link "$TEST_TMP/link"
    [ "$status" -eq 0 ]
}

@test "is_envup_link: does not claim a link into someone else's directory" {
    # The guard on every rm -f. A false positive here deletes a user's own file.
    _nfs_layout
    ENVUP_HOME="$TEST_TMP/mnt/home/me/envup"
    mkdir -p "$TEST_TMP/mnt/home/me/other"; : > "$TEST_TMP/mnt/home/me/other/zshrc"
    ln -s "$TEST_TMP/mnt/home/me/other/zshrc" "$TEST_TMP/link"
    run is_envup_link "$TEST_TMP/link"
    [ "$status" -ne 0 ]
}

@test "is_envup_link: a plain file is never claimed" {
    ENVUP_HOME="$TEST_TMP"
    : > "$TEST_TMP/plain"
    run is_envup_link "$TEST_TMP/plain"
    [ "$status" -ne 0 ]
}

@test "is_envup_link: refuses to treat / as the repo" {
    # ENVUP_HOME=/ would make the prefix test match every symlink on the machine.
    ENVUP_HOME=/
    ln -s /etc/hosts "$TEST_TMP/link"
    run is_envup_link "$TEST_TMP/link"
    [ "$status" -ne 0 ]
}

@test "unlink_safe: removes an envup link reached through the aliased home (C4)" {
    # The end-to-end shape of the bug: uninstall silently left everything behind.
    _nfs_layout
    ENVUP_HOME="$NFS_HOME/me/envup"
    ln -s "$TEST_TMP/mnt/home/me/envup/zshrc" "$TEST_TMP/dotfile"
    run unlink_safe "$TEST_TMP/dotfile"
    [ "$status" -eq 0 ]
    [ ! -L "$TEST_TMP/dotfile" ]
}

# ---- link idempotence (C5) -----------------------------------------------

@test "_link: an existing correct link is left alone, not rebuilt (C5)" {
    _nfs_layout
    ENVUP_HOME="$TEST_TMP/mnt/home/me/envup"
    # Pre-existing link written through the *other* name for the same file —
    # which is what happens when the repo was installed from the aliased path.
    ln -s "$NFS_HOME/me/envup/zshrc" "$TEST_TMP/dst"

    run safe_link "$ENVUP_HOME/zshrc" "$TEST_TMP/dst"
    [ "$status" -eq 0 ]
    [[ "$output" == *"already linked"* ]]
    # And it really was untouched: the target still reads the way it was written.
    [ "$(readlink "$TEST_TMP/dst")" = "$NFS_HOME/me/envup/zshrc" ]
}

@test "_link: a link pointing somewhere else is replaced" {
    _nfs_layout
    ENVUP_HOME="$TEST_TMP/mnt/home/me/envup"
    : > "$TEST_TMP/elsewhere"
    ln -s "$TEST_TMP/elsewhere" "$TEST_TMP/dst"

    run safe_link "$ENVUP_HOME/zshrc" "$TEST_TMP/dst"
    [ "$status" -eq 0 ]
    [ "$(readlink "$TEST_TMP/dst")" = "$ENVUP_HOME/zshrc" ]
}

@test "_link: a real file at the destination is backed up before it is replaced (I1)" {
    _nfs_layout
    ENVUP_HOME="$TEST_TMP/mnt/home/me/envup"
    echo "the user's own config" > "$TEST_TMP/dst"

    run safe_link "$ENVUP_HOME/zshrc" "$TEST_TMP/dst"
    [ "$status" -eq 0 ]
    [ -L "$TEST_TMP/dst" ]
    grep -qr "the user's own config" "$ENVUP_BACKUP_DIR"
}
