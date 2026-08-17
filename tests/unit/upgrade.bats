#!/usr/bin/env bats
# `envup upgrade` moves the checkout forward. It was the least-tested command in
# the repo, and the one whose failure mode collides with the design: configs are
# symlinks *into* the checkout, so the working tree is in daily use and a plain
# `git pull` fails for reasons that have nothing to do with the upgrade.
#
# Everything here runs against a real git repo with a real (local) remote. A
# stubbed git would pass whatever the diagnosis expects, which is the one thing
# these tests must not do — the whole point is telling a dirty tree apart from a
# detached HEAD apart from a missing upstream.

load '../test_helper'

setup() {
    common_setup
    if ! have git; then skip "git is not installed"; fi
    git config --global --get user.email >/dev/null 2>&1 || export GIT_AUTHOR_EMAIL=t@example.invalid
    export GIT_AUTHOR_NAME="${GIT_AUTHOR_NAME:-envup test}"
    export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME"
    export GIT_COMMITTER_EMAIL="${GIT_AUTHOR_EMAIL:-t@example.invalid}"
    export GIT_AUTHOR_EMAIL="$GIT_COMMITTER_EMAIL"
    mk_repo
}
teardown() { common_teardown; }

# A bare origin plus a clone at $ENVUP_HOME, with one tracked config file that
# stands in for a module's files/ — the kind of file a symlink points at.
mk_repo() {
    ORIGIN="$TEST_TMP/origin.git"
    git init -q --bare "$ORIGIN"
    WORK="$TEST_TMP/work"
    git clone -q "$ORIGIN" "$WORK" 2>/dev/null
    mkdir -p "$WORK/modules/zsh/files"
    echo "# v1" > "$WORK/modules/zsh/files/.zshrc"
    echo "# envup" > "$WORK/README.md"
    git -C "$WORK" add -A
    git -C "$WORK" commit -q -m "v1"
    git -C "$WORK" tag -a v1 -m v1
    git -C "$WORK" push -q origin HEAD --tags 2>/dev/null
    # `git init` picks the default branch name from the machine's config, so
    # the tests have to ask rather than assume master or main.
    BRANCH="$(git -C "$WORK" symbolic-ref --short HEAD)"

    # $ENVUP_HOME is a second clone: the machine being upgraded. common_setup
    # left lib.sh/lib symlinks in there; keep them and let git ignore them.
    rm -rf "$ENVUP_HOME"
    git clone -q "$ORIGIN" "$ENVUP_HOME" 2>/dev/null
    # envup resolves ENVUP_HOME from its own path, and BASH_SOURCE follows the
    # symlink's name — so the CLI run against this clone is the same trick
    # common_setup already uses for lib.sh.
    ln -sf "$REPO_ROOT/lib.sh" "$ENVUP_HOME/lib.sh"
    ln -sf "$REPO_ROOT/lib"    "$ENVUP_HOME/lib"
    ln -sf "$REPO_ROOT/envup"  "$ENVUP_HOME/envup"
    printf 'lib.sh\nlib\nenvup\n' > "$ENVUP_HOME/.git/info/exclude"
}

# push_upstream <text> — a new commit on origin for the machine to pull.
push_upstream() {
    echo "$1" > "$WORK/modules/zsh/files/.zshrc"
    git -C "$WORK" commit -q -am "$1"
    git -C "$WORK" push -q origin HEAD 2>/dev/null
}

# ---- the happy path -------------------------------------------------------

@test "upgrade_source: pulls the branch forward" {
    push_upstream "# v2"
    run upgrade_source
    [ "$status" -eq 0 ]
    [ "$(cat "$ENVUP_HOME/modules/zsh/files/.zshrc")" = "# v2" ]
}

@test "upgrade_source: already up to date is success, not a no-op failure" {
    run upgrade_source
    [ "$status" -eq 0 ]
}

@test "upgrade_source: --ref checks out a tag" {
    push_upstream "# v2"
    upgrade_source
    run upgrade_source v1
    [ "$status" -eq 0 ]
    [ "$(cat "$ENVUP_HOME/modules/zsh/files/.zshrc")" = "# v1" ]
}

@test "upgrade_source: --ref back to a branch reattaches HEAD" {
    upgrade_source v1                       # detach
    [ -z "$(_upgrade_branch)" ]
    run upgrade_source "$BRANCH"
    [ "$status" -eq 0 ]
    [ -n "$(_upgrade_branch)" ]
}

@test "upgrade_source: dry-run touches nothing" {
    push_upstream "# v2"
    ENVUP_DRY_RUN=1 run upgrade_source
    [ "$status" -eq 0 ]
    [ "$(cat "$ENVUP_HOME/modules/zsh/files/.zshrc")" = "# v1" ]
}

# ---- the failures this repo actually produces -----------------------------

@test "a config edited through its symlink is named, and points at envup adopt" {
    # What nvm's installer did to this repo: append to a tracked file that a
    # ~/.zshrc symlink resolves to.
    echo 'export NVM_DIR="$HOME/.nvm"' >> "$ENVUP_HOME/modules/zsh/files/.zshrc"
    push_upstream "# v2"

    run upgrade_source
    [ "$status" -ne 0 ]
    [[ "$output" == *"modules/zsh/files/.zshrc"* ]]
    [[ "$output" == *"envup adopt"* ]]
    [[ "$output" == *"wrote through the link"* ]]
}

@test "an uncommitted change outside modules/ says stash, not adopt" {
    # git only refuses a pull that would have to overwrite the dirty file, so
    # the upstream commit has to touch the same one.
    echo "local edit" >> "$ENVUP_HOME/README.md"
    echo "upstream edit" >> "$WORK/README.md"
    git -C "$WORK" commit -q -am readme
    git -C "$WORK" push -q origin HEAD 2>/dev/null

    run upgrade_source
    [ "$status" -ne 0 ]
    [[ "$output" == *"README.md"* ]]
    [[ "$output" == *"stash"* ]]
    [[ "$output" != *"envup adopt"* ]]
}

@test "a detached HEAD is caught before the network, with the way back" {
    upgrade_source v1
    run upgrade_source
    [ "$status" -ne 0 ]
    [[ "$output" == *"detached"* ]]
    [[ "$output" == *"--ref main"* ]]   # the hint names the usual branch
    # Caught locally: no fetch was attempted.
    [[ "$output" != *"git pull ("* ]]
}

@test "a branch with no upstream is named as such" {
    git -C "$ENVUP_HOME" checkout -q -b orphan
    run upgrade_source
    [ "$status" -ne 0 ]
    [[ "$output" == *"orphan"* ]]
    [[ "$output" == *"not tracking anything"* ]]
    [[ "$output" == *"--set-upstream-to"* ]]
}

@test "--ref with a name that does not exist says so instead of blaming the tree" {
    run upgrade_source v99
    [ "$status" -ne 0 ]
    [[ "$output" == *"no tag or branch called 'v99'"* ]]
}

@test "--ref onto a dirty tree reports the dirt, not a missing tag" {
    # The checkout has to actually need to overwrite the dirty file, so move
    # the machine to v2 first and then ask for v1 back.
    push_upstream "# v2"; git -C "$WORK" tag -a v2 -m v2
    git -C "$WORK" push -q origin HEAD --tags 2>/dev/null
    upgrade_source
    echo 'polluted' >> "$ENVUP_HOME/modules/zsh/files/.zshrc"
    run upgrade_source v1
    [ "$status" -ne 0 ]
    [[ "$output" == *"envup adopt"* ]]
    [[ "$output" != *"no tag or branch"* ]]
}

@test "a checkout that is not a git repo is diagnosed, not left to git" {
    rm -rf "$ENVUP_HOME/.git"
    run upgrade_source
    [ "$status" -ne 0 ]
    [[ "$output" == *"not a git checkout"* ]]
    [[ "$output" == *"git clone"* ]]
}

@test "no git at all is its own message" {
    isolate_path
    rm -f "$STUB_BIN/git" "$TEST_TMP/isolated-bin/git"
    run upgrade_source
    [ "$status" -ne 0 ]
    [[ "$output" == *"git is not installed"* ]]
}

# ---- submodules are moving parts, not obstacles ---------------------------

@test "a plugin submodule at a different commit does not count as a dirty tree" {
    # Submodules track plugin state and move on their own; treating that as
    # pollution would make every machine with updated plugins unupgradable.
    sub="$TEST_TMP/sub.git"
    git init -q --bare "$sub"
    tmp="$TEST_TMP/subwork"; git clone -q "$sub" "$tmp" 2>/dev/null
    echo one > "$tmp/f"; git -C "$tmp" add -A; git -C "$tmp" commit -q -m one
    git -C "$tmp" push -q origin HEAD 2>/dev/null

    git -C "$ENVUP_HOME" -c protocol.file.allow=always submodule add -q "$sub" modules/zsh/files/plugins/p 2>/dev/null || skip "submodule add refused"
    git -C "$ENVUP_HOME" commit -q -m "add plugin"
    git -C "$ENVUP_HOME" push -q origin HEAD 2>/dev/null

    echo two > "$tmp/f"; git -C "$tmp" commit -q -am two; git -C "$tmp" push -q origin HEAD 2>/dev/null
    git -C "$ENVUP_HOME/modules/zsh/files/plugins/p" fetch -q origin 2>/dev/null
    git -C "$ENVUP_HOME/modules/zsh/files/plugins/p" reset -q --hard origin/HEAD 2>/dev/null

    run _upgrade_dirty
    [ "$status" -ne 0 ]        # nothing to report
}

# ---- the CLI wrapper ------------------------------------------------------

@test "envup upgrade: a failed update stops before reinstalling" {
    echo 'polluted' >> "$ENVUP_HOME/modules/zsh/files/.zshrc"
    push_upstream "# v2"
    run "$ENVUP_HOME/envup" upgrade
    [ "$status" -ne 0 ]
    [[ "$output" == *"envup adopt"* ]]
    [[ "$output" == *"--keep-going"* ]]
    [[ "$output" != *"install order"* ]]
}

@test "envup upgrade --keep-going: reinstalls anyway and still says the source is old" {
    echo 'polluted' >> "$ENVUP_HOME/modules/zsh/files/.zshrc"
    push_upstream "# v2"
    run "$ENVUP_HOME/envup" upgrade --keep-going
    [[ "$output" == *"reinstalled the OLD source"* ]] || [[ "$output" == *"nothing installed to upgrade"* ]]
}

@test "envup upgrade --dry-run: previews without touching the checkout" {
    push_upstream "# v2"
    run "$ENVUP_HOME/envup" upgrade --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"[dry-run]"* ]]
    [ "$(cat "$ENVUP_HOME/modules/zsh/files/.zshrc")" = "# v1" ]
}
