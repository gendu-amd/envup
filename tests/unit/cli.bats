#!/usr/bin/env bats
# The dispatcher's argument handling.
#
# Two things are being pinned here, and both are about what happens when the
# command line is *wrong*:
#
#   1. No option can hang. envup's headline promise is that no step can hang the
#      whole run, and every network call is time-boxed to keep it — which was
#      worth very little while `envup upgrade --profile` with the value left off
#      spun forever in the argument loop, before any of that machinery ran.
#      `shift 2` with one argument remaining fails *without shifting*, so
#      `while (($#))` never advances.
#
#   2. A wrong option is refused, not ignored. Printing the human table for
#      `status --jsonn` is the worst available answer for a script that asked
#      for JSON, and reading it back is how you find out.

load '../test_helper'

setup() {
    common_setup
    # envup derives ENVUP_HOME from its real file, so the fixture needs its own
    # entry point. A symlink would correctly resolve back to the real checkout.
    cp "$REPO_ROOT/envup"       "$ENVUP_HOME/envup"
    ln -sf "$REPO_ROOT/VERSION" "$ENVUP_HOME/VERSION"
    mkdir -p "$ENVUP_HOME/profiles"
}
teardown() { common_teardown; }

@test "the global ~/.local/bin-style symlink resolves the real repo" {
    local bindir="$TEST_TMP/user-bin"
    mkdir -p "$bindir"
    ln -s "$REPO_ROOT/envup" "$bindir/envup"

    # There is deliberately no lib.sh beside this link. Production installs
    # have exactly this shape: ~/.local/bin/envup -> <checkout>/envup.
    run "$bindir/envup" version
    [ "$status" -eq 0 ]
    [ "$output" = "envup $(cat "$REPO_ROOT/VERSION")" ]
}

# Every option that takes a value, invoked with the value missing. The table is
# the point: an option added later gets a line here and is covered for free.
@test "no command hangs when an option's value is missing" {
    local args
    for args in "install --profile" "install -p" "install --tools" \
                "upgrade --profile" "upgrade -p" \
                "upgrade --ref"     "upgrade -r" \
                "upgrade --tools" \
                "doctor --module"; do
        # shellcheck disable=SC2086  # deliberate word splitting of the table row
        run timeout 10 "$ENVUP_HOME/envup" $args
        [ "$status" -ne 124 ] || { echo "hung: envup $args"; return 1; }
        [ "$status" -ne 0 ]   || { echo "silently accepted: envup $args"; return 1; }
    done
}

@test "upgrade --profile with no value names the option it is complaining about" {
    run timeout 10 "$ENVUP_HOME/envup" upgrade --profile
    [ "$status" -eq 1 ]
    [[ "$output" == *"--profile needs a name"* ]]
}

@test "upgrade reloads the selected CLI and forwards an explicit locked policy" {
    mk_module fixture
    manifest_add fixture
    rm "$ENVUP_HOME/lib.sh"
    {
        printf 'source %q\n' "$REPO_ROOT/lib.sh"
        cat <<'EOF'
upgrade_source() {
    cat > "$ENVUP_HOME/envup" <<'INNER'
#!/bin/bash
printf 'selected CLI: %s; policy=%s\n' "$*" "$ENVUP_TOOL_POLICY"
INNER
}
EOF
    } > "$ENVUP_HOME/lib.sh"
    run "$ENVUP_HOME/envup" upgrade --tools locked
    [ "$status" -eq 0 ]
    [[ "$output" == *'selected CLI: install --tools locked fixture; policy=locked'* ]]
}

@test "a misspelt tool policy is rejected before source update or installation" {
    run "$ENVUP_HOME/envup" upgrade --tools lastest
    [ "$status" -eq 1 ]
    [[ "$output" == *'--tools needs reuse or locked'* ]]
    [ ! -e "$ENVUP_MANIFEST" ]
    run "$ENVUP_HOME/envup" install --tools lastest
    [ "$status" -eq 1 ]
    [ ! -e "$ENVUP_MANIFEST" ]
}

@test "status: a misspelt option is refused, not answered with the wrong format" {
    run "$ENVUP_HOME/envup" status --jsonn
    [ "$status" -ne 0 ]
    [[ "$output" == *"unknown option"* ]]
    [[ "$output" != *"Modules:"* ]]
}

@test "status: --json and no-args both still work" {
    run "$ENVUP_HOME/envup" status --json
    [ "$status" -eq 0 ]
    [[ "$output" == "{"* ]]
    run "$ENVUP_HOME/envup" status
    [ "$status" -eq 0 ]
    [[ "$output" == *"Modules:"* ]]
}

@test "log: --help prints usage instead of dumping a log" {
    run "$ENVUP_HOME/envup" log --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: envup log"* ]]
}

@test "log: a misspelt option is refused" {
    run "$ENVUP_HOME/envup" log --tial
    [ "$status" -ne 0 ]
    [[ "$output" == *"unknown option"* ]]
}

# `--dry-runn` used to be reported as "no module: dry-runn", which sends you
# looking for a module instead of at the flag you mistyped.
@test "clean: a misspelt option is reported as an option, not as a module" {
    run "$ENVUP_HOME/envup" clean --dry-runn
    [ "$status" -ne 0 ]
    [[ "$output" == *"unknown option"* ]]
}

@test "clean nvim: removes cache and keeps plugins, editor state and private files" {
    mkdir -p "$ENVUP_HOME/modules/nvim" "$HOME/.cache/nvim" \
        "$HOME/.local/share/nvim/lazy" "$HOME/.local/state/nvim/shada" "$HOME/.config/nvim"
    cp "$REPO_ROOT/modules/nvim/meta.sh" "$ENVUP_HOME/modules/nvim/meta.sh"
    echo cached > "$HOME/.cache/nvim/cache"
    echo plugin > "$HOME/.local/share/nvim/lazy/plugin"
    echo history > "$HOME/.local/state/nvim/shada/main.shada"
    echo private > "$HOME/.config/nvim/local.lua"
    run "$ENVUP_HOME/envup" clean nvim
    [ "$status" -eq 0 ]
    [ ! -e "$HOME/.cache/nvim" ]
    [ "$(cat "$HOME/.local/share/nvim/lazy/plugin")" = plugin ]
    [ "$(cat "$HOME/.local/state/nvim/shada/main.shada")" = history ]
    [ "$(cat "$HOME/.config/nvim/local.lua")" = private ]
}

@test "clean: wildcard cache paths with spaces are removed without splitting" {
    mk_module cache
    printf 'CLEAN_PATHS=("$HOME/.cache/cache dir/"*)\n' >> "$ENVUP_HOME/modules/cache/meta.sh"
    mkdir -p "$HOME/.cache/cache dir/one" "$HOME/.cache/cache dir/two"
    echo mine > "$HOME/keep"
    run "$ENVUP_HOME/envup" clean cache
    [ "$status" -eq 0 ]
    [ ! -e "$HOME/.cache/cache dir/one" ]
    [ ! -e "$HOME/.cache/cache dir/two" ]
    [ "$(cat "$HOME/keep")" = mine ]
}

@test "clean: refuses HOME, editor data, the cache root and managed source trees" {
    mk_module unsafe
    printf 'CLEAN_PATHS=("$HOME" "$HOME/.cache" "$HOME/.local/share/nvim" "$ENVUP_HOME")\n' \
        >> "$ENVUP_HOME/modules/unsafe/meta.sh"
    mkdir -p "$HOME/.cache" "$HOME/.local/share/nvim"
    echo mine > "$HOME/.local/share/nvim/keep"
    run "$ENVUP_HOME/envup" clean unsafe
    [ "$status" -ne 0 ]
    [[ "$output" == *"refusing unsafe cache path"* ]]
    [ -f "$ENVUP_HOME/modules/unsafe/meta.sh" ]
    [ "$(cat "$HOME/.local/share/nvim/keep")" = mine ]
}

@test "clean: a symlinked parent cannot redirect cleanup into user data" {
    mk_module unsafe
    printf 'CLEAN_PATHS=("$HOME/.cache/escape/keep")\n' >> "$ENVUP_HOME/modules/unsafe/meta.sh"
    mkdir -p "$HOME/.cache" "$HOME/Documents"
    echo mine > "$HOME/Documents/keep"
    ln -s "$HOME/Documents" "$HOME/.cache/escape"
    run "$ENVUP_HOME/envup" clean unsafe
    [ "$status" -ne 0 ]
    [ "$(cat "$HOME/Documents/keep")" = mine ]
}

@test "clean: deletion errors fail the command instead of reporting success" {
    mk_module cache
    printf 'CLEAN_PATHS=("$HOME/.cache/test")\n' >> "$ENVUP_HOME/modules/cache/meta.sh"
    mkdir -p "$HOME/.cache/test"
    stub_bin rm <<'SH'
#!/bin/sh
echo 'removal denied' >&2
exit 1
SH
    run "$ENVUP_HOME/envup" clean cache
    [ "$status" -ne 0 ]
    [[ "$output" == *"cache removal failed"* ]]
    [[ "$output" != *"cleared 1 path"* ]]
    [ -d "$HOME/.cache/test" ]
}

@test "clean: Oh-My-Zsh cache cannot point through a parent into user files" {
    mk_module unsafe
    printf 'CLEAN_PATHS=("$HOME/.oh-my-zsh/cache/keep")\n' >> "$ENVUP_HOME/modules/unsafe/meta.sh"
    mkdir -p "$HOME/Documents/cache"
    echo mine > "$HOME/Documents/cache/keep"
    ln -s "$HOME/Documents" "$HOME/.oh-my-zsh"
    run "$ENVUP_HOME/envup" clean unsafe
    [ "$status" -ne 0 ]
    [ "$(cat "$HOME/Documents/cache/keep")" = mine ]
}

@test "clean: dry-run respects XDG cache paths and removes nothing" {
    mk_module cache
    export XDG_CACHE_HOME="$TEST_TMP/xdg cache"
    printf 'CLEAN_PATHS=("${XDG_CACHE_HOME}/test")\n' >> "$ENVUP_HOME/modules/cache/meta.sh"
    mkdir -p "$XDG_CACHE_HOME/test"
    run "$ENVUP_HOME/envup" clean --dry-run cache
    [ "$status" -eq 0 ]
    [[ "$output" == *"[dry-run] rm -rf $XDG_CACHE_HOME/test"* ]]
    [ -d "$XDG_CACHE_HOME/test" ]
}

@test "uninstall: failed unlink keeps the manifest and does not run post_uninstall" {
    mk_module blocked
    mkdir -p "$ENVUP_HOME/files"
    echo shared > "$ENVUP_HOME/files/config"
    printf 'LINKS=("files/config:$HOME/.blocked")\n' >> "$ENVUP_HOME/modules/blocked/meta.sh"
    printf 'post_uninstall() { touch "$HOME/post-ran"; }\n' > "$ENVUP_HOME/modules/blocked/hooks.sh"
    ln -s "$ENVUP_HOME/files/config" "$HOME/.blocked"
    manifest_record blocked ok
    stub_bin rm <<'SH'
#!/bin/sh
echo 'unlink denied' >&2
exit 1
SH
    run "$ENVUP_HOME/envup" uninstall blocked
    [ "$status" -ne 0 ]
    [[ "$output" == *"unlinking failed"* ]]
    [[ "$output" != *"uninstall complete"* ]]
    [ -L "$HOME/.blocked" ]
    [ ! -e "$HOME/post-ran" ]
    manifest_has blocked
}

@test "uninstall: failed state removal is reported and retains the installed row" {
    mk_module blocked
    manifest_record blocked ok
    stub_bin mv <<'SH'
#!/bin/sh
echo 'state replacement denied' >&2
exit 1
SH
    run "$ENVUP_HOME/envup" uninstall blocked
    [ "$status" -ne 0 ]
    [[ "$output" == *"uninstall failed for: blocked"* ]]
    [[ "$output" != *"uninstall complete"* ]]
    manifest_has blocked
}

@test "install: bad dependency plans fail before any hook or configuration change" {
    local bad args
    mk_module a missing
    mk_module b c
    mk_module c b
    for bad in a b c; do
        printf 'pre_install() { touch "$HOME/hook-ran"; }\n' > "$ENVUP_HOME/modules/$bad/hooks.sh"
    done
    for args in 'a' 'b' 'a --dry-run' 'b --dry-run'; do
        # shellcheck disable=SC2086
        run timeout 10 "$ENVUP_HOME/envup" install $args
        [ "$status" -eq 1 ]
        [ ! -e "$HOME/hook-ran" ]
        [ ! -e "$ENVUP_STATE_DIR/installed" ]
    done
}

@test "install: validates transitive module metadata before running earlier modules" {
    mk_module a b
    mk_module b
    printf 'DESCRIPTION="fixture"\nPROVIDERS=(unknown:argument)\n' >> "$ENVUP_HOME/modules/a/meta.sh"
    printf 'DESCRIPTION="fixture"\n' >> "$ENVUP_HOME/modules/b/meta.sh"
    printf 'pre_install() { touch "$HOME/hook-ran"; }\n' > "$ENVUP_HOME/modules/b/hooks.sh"
    run "$ENVUP_HOME/envup" install a
    [ "$status" -eq 1 ]
    [[ "$output" == *"unknown provider"* ]]
    [ ! -e "$HOME/hook-ran" ]
    [ ! -e "$ENVUP_STATE_DIR/installed" ]
}

@test "install: rejects conflicting links in the selected dependency closure" {
    mk_module a b
    mk_module b
    mkdir -p "$ENVUP_HOME/files" "$HOME/real"
    ln -s "$HOME/real" "$HOME/alias"
    echo first > "$ENVUP_HOME/files/first"
    echo second > "$ENVUP_HOME/files/second"
    printf 'DESCRIPTION="fixture"\nLINKS=("files/first:$HOME/real/config")\n' >> "$ENVUP_HOME/modules/a/meta.sh"
    printf 'DESCRIPTION="fixture"\nLINKS=("files/second:$HOME/alias/config")\n' >> "$ENVUP_HOME/modules/b/meta.sh"
    run "$ENVUP_HOME/envup" install a
    [ "$status" -eq 1 ]
    [[ "$output" == *"already claimed"* ]]
    [ ! -e "$HOME/real/config" ]
    [ ! -e "$ENVUP_STATE_DIR/installed" ]
}

@test "install: unrelated broken metadata does not prevent installing a valid selection" {
    mk_module good
    mk_module unrelated
    printf 'DESCRIPTION="fixture"\n' >> "$ENVUP_HOME/modules/good/meta.sh"
    printf 'PROVIDERS=(unknown)\n' >> "$ENVUP_HOME/modules/unrelated/meta.sh"
    run "$ENVUP_HOME/envup" install good
    [ "$status" -eq 0 ]
    manifest_has good
}

@test "install: rejects conflicting or nested links within one module" {
    mk_module config
    mkdir -p "$ENVUP_HOME/files"
    echo shared > "$ENVUP_HOME/files/first"
    echo other > "$ENVUP_HOME/files/second"
    printf 'DESCRIPTION="fixture"\nLINKS=("files/first:$HOME/config" "files/second:$HOME/config")\n' \
        >> "$ENVUP_HOME/modules/config/meta.sh"
    run "$ENVUP_HOME/envup" install config
    [ "$status" -eq 1 ]
    [[ "$output" == *"already claimed"* ]]
    printf 'LINKS=("files:$HOME/config" "files/second:$HOME/config/second")\n' \
        >> "$ENVUP_HOME/modules/config/meta.sh"
    run "$ENVUP_HOME/envup" install config --dry-run
    [ "$status" -eq 1 ]
    [[ "$output" == *"overlaps"* ]]
    [ ! -e "$HOME/config" ]
    [ "$(cat "$ENVUP_HOME/files/second")" = other ]
    [ ! -e "$ENVUP_STATE_DIR/installed" ]
    ln -s "$ENVUP_HOME/files" "$HOME/config"
    run "$ENVUP_HOME/envup" install config
    [ "$status" -eq 1 ]
    [[ "$output" == *"overlaps"* ]]
    [ "$(readlink "$HOME/config")" = "$ENVUP_HOME/files" ]
    [ "$(cat "$ENVUP_HOME/files/second")" = other ]
    [ ! -e "$ENVUP_STATE_DIR/installed" ]
}

@test "install: an absent optional link does not conflict with an active link" {
    mk_module config optional
    mk_module optional
    mkdir -p "$ENVUP_HOME/files"
    echo shared > "$ENVUP_HOME/files/first"
    printf 'DESCRIPTION="fixture"\nLINKS=("files/first:$HOME/config")\n' \
        >> "$ENVUP_HOME/modules/config/meta.sh"
    printf 'DESCRIPTION="fixture"\nLINKS=("?files/missing:$HOME/config")\n' \
        >> "$ENVUP_HOME/modules/optional/meta.sh"
    run "$ENVUP_HOME/envup" install config --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"install order: optional config"* ]]
    [ ! -e "$HOME/config" ]
    [ ! -e "$ENVUP_STATE_DIR/installed" ]
    [ ! -e "$ENVUP_STATE_DIR/root" ]
    [ ! -e "$ENVUP_BACKUP_DIR" ]
    echo other > "$ENVUP_HOME/files/second"
    printf 'LINKS=("?%s:$HOME/config")\n' "$ENVUP_HOME/files/second" \
        >> "$ENVUP_HOME/modules/optional/meta.sh"
    run "$ENVUP_HOME/envup" install config --dry-run
    [ "$status" -eq 1 ]
    [[ "$output" == *"already claimed"* ]]
    [ ! -e "$HOME/config" ]
}

@test "install: a missing required link source fails before any module runs" {
    mk_module a b
    mk_module b
    printf 'DESCRIPTION="fixture"\nLINKS=("files/missing:$HOME/config")\n' \
        >> "$ENVUP_HOME/modules/a/meta.sh"
    printf 'DESCRIPTION="fixture"\n' >> "$ENVUP_HOME/modules/b/meta.sh"
    printf 'pre_install() { touch "$HOME/hook-ran"; }\n' > "$ENVUP_HOME/modules/b/hooks.sh"
    run "$ENVUP_HOME/envup" install a
    [ "$status" -eq 1 ]
    [[ "$output" == *"source does not exist"* ]]
    [ ! -e "$HOME/hook-ran" ]
    [ ! -e "$HOME/config" ]
    [ ! -e "$ENVUP_STATE_DIR/installed" ]
}

@test "install: malformed hooks are rejected before earlier modules run" {
    mk_module a b
    mk_module b
    printf 'DESCRIPTION="fixture"\n' >> "$ENVUP_HOME/modules/a/meta.sh"
    printf 'DESCRIPTION="fixture"\n' >> "$ENVUP_HOME/modules/b/meta.sh"
    printf 'post_install() {\n' > "$ENVUP_HOME/modules/a/hooks.sh"
    printf 'pre_install() { touch "$HOME/hook-ran"; }\n' > "$ENVUP_HOME/modules/b/hooks.sh"
    run "$ENVUP_HOME/envup" install a
    [ "$status" -eq 1 ]
    [[ "$output" == *"syntax error"* ]]
    [ ! -e "$HOME/hook-ran" ]
    [ ! -e "$ENVUP_STATE_DIR/installed" ]
}

@test "install: a failed profile load is not treated as a usable partial selection" {
    mk_module a
    printf 'DESCRIPTION="fixture"\n' >> "$ENVUP_HOME/modules/a/meta.sh"
    printf 'pre_install() { touch "$HOME/hook-ran"; }\n' > "$ENVUP_HOME/modules/a/hooks.sh"
    printf 'MODULES=(a)\nreturn 1\n' > "$ENVUP_HOME/profiles/broken.sh"
    run "$ENVUP_HOME/envup" install --profile broken
    [ "$status" -eq 1 ]
    [ ! -e "$HOME/hook-ran" ]
    [ ! -e "$ENVUP_STATE_DIR/installed" ]
}

@test "install: a provider error followed by manual guidance makes the command fail" {
    mk_module broken
    printf 'DESCRIPTION="fixture"\nVERIFY_BIN="definitely-not-a-real-binary"\nPROVIDERS=(git manual)\n' \
        >> "$ENVUP_HOME/modules/broken/meta.sh"
    run "$ENVUP_HOME/envup" install broken
    [ "$status" -eq 1 ]
    [[ "$output" == *"git provider needs GIT_URL"* ]]
    [[ "$output" == *"failed:   broken"* ]]
    [[ "$output" != *"degraded: broken"* ]]
}

@test "status: last failed install is visible alongside current healthy state" {
    mk_module good
    printf 'DESCRIPTION="fixture"\n' >> "$ENVUP_HOME/modules/good/meta.sh"
    manifest_record good ok system 1.0
    manifest_install_record good failed post_install $'failed "setup"\\path\nnext'
    run "$ENVUP_HOME/envup" status
    [ "$status" -eq 0 ]
    [[ "$output" == *'last install: failed (post_install)'* ]]
    run "$ENVUP_HOME/envup" status --json
    [ "$status" -eq 0 ]
    printf '%s' "$output" > "$TEST_TMP/status.json"
    run python3 -c 'import json,sys; m=json.load(open(sys.argv[1]))["modules"][0]; assert m["state"]=="ok" and m["installed"] is True; assert m["version"]=="1.0"; assert m["last_install"]["state"]=="failed"; assert m["last_install"]["reason"]=="failed \"setup\"\\path next"' "$TEST_TMP/status.json"
    [ "$status" -eq 0 ]
}

@test "status: legacy modules have no fabricated installation attempt" {
    mk_module legacy
    printf 'DESCRIPTION="fixture"\n' >> "$ENVUP_HOME/modules/legacy/meta.sh"
    manifest_add legacy
    run "$ENVUP_HOME/envup" status --json
    [ "$status" -eq 0 ]
    [[ "$output" == *'"last_install":null'* ]]
    [ -z "$(manifest_install_list)" ]
}

@test "install, status and doctor agree on missing components with a healthy tool" {
    mk_module cfg
    printf 'DESCRIPTION="fixture"\n' >> "$ENVUP_HOME/modules/cfg/meta.sh"
    printf 'check_health() { echo "component missing"; return 70; }\n' > "$ENVUP_HOME/modules/cfg/hooks.sh"
    run "$ENVUP_HOME/envup" install cfg
    [ "$status" -eq 0 ]
    [[ "$output" == *"degraded: cfg"* ]]
    run "$ENVUP_HOME/envup" status --json
    [ "$status" -eq 0 ]
    printf '%s' "$output" > "$TEST_TMP/status.json"
    run python3 -c 'import json,sys; m=json.load(open(sys.argv[1]))["modules"][0]; assert m["state"]=="degraded"; assert m["check"]["detail"]=="component missing"' "$TEST_TMP/status.json"
    [ "$status" -eq 0 ]
    run "$ENVUP_HOME/envup" doctor --module cfg
    [ "$status" -eq 0 ]
    [[ "$output" == *"component missing"* ]]
    [[ "$output" != *"starts working the moment the tool exists"* ]]
    run "$ENVUP_HOME/envup" status
    [[ "$output" == *"component missing"* ]]
}

@test "standalone enhancements install without adopting the user's shell or Git config" {
    local m
    unset ENVUP_ATUIN_INSTALL
    printf 'private shell\n' > "$HOME/.zshrc"
    printf 'private git\n' > "$HOME/.gitconfig"
    printf 'private pager\n' > "$HOME/.gitconfig.envup"
    for m in zoxide atuin direnv delta; do
        mkdir -p "$ENVUP_HOME/modules/$m"
        cp "$REPO_ROOT/modules/$m/meta.sh" "$ENVUP_HOME/modules/$m/meta.sh"
        if [[ -f "$REPO_ROOT/modules/$m/hooks.sh" ]]; then
            cp "$REPO_ROOT/modules/$m/hooks.sh" "$ENVUP_HOME/modules/$m/hooks.sh"
        fi
        printf '#!/bin/bash\necho tool-1.0\n' > "$STUB_BIN/$m"
        chmod +x "$STUB_BIN/$m"
        run "$ENVUP_HOME/envup" install "$m"
        [ "$status" -eq 0 ]
        [[ "$output" == *"install order: $m"* ]]
        manifest_has "$m"
        ! manifest_has zsh
        ! manifest_has git
        [ "$(cat "$HOME/.zshrc")" = 'private shell' ]
        [ "$(cat "$HOME/.gitconfig")" = 'private git' ]
        [ "$(cat "$HOME/.gitconfig.envup")" = 'private pager' ]
    done
}

@test "status: a timed out probe does not imply installation ownership" {
    mk_module cfg
    printf 'DESCRIPTION="fixture"\nVERIFY_BIN=hung\n' >> "$ENVUP_HOME/modules/cfg/meta.sh"
    stub_bin hung <<'EOF'
#!/bin/bash
sleep 30
EOF
    ENVUP_HEALTH_TIMEOUT=1 run "$ENVUP_HOME/envup" status --json
    [ "$status" -eq 0 ]
    printf '%s' "$output" > "$TEST_TMP/status.json"
    run python3 -c 'import json,sys; m=json.load(open(sys.argv[1]))["modules"][0]; assert m["state"]=="unknown" and m["installed"] is False' "$TEST_TMP/status.json"
    [ "$status" -eq 0 ]
}

@test "install: a checkout-root record failure makes the command fail" {
    mk_module good
    printf 'DESCRIPTION="fixture"\n' >> "$ENVUP_HOME/modules/good/meta.sh"
    # The shared fixture library is a symlink; inject the error in a private copy.
    rm "$ENVUP_HOME/lib"
    cp -R "$REPO_ROOT/lib" "$ENVUP_HOME/lib"
    printf '\nmanifest_set_root() { return 1; }\n' >> "$ENVUP_HOME/lib/manifest.sh"
    run "$ENVUP_HOME/envup" install good
    [ "$status" -eq 1 ]
    [[ "$output" == *"could not record checkout root"* ]]
}

@test "install: environment-variable dry-run writes neither attempts nor checkout root" {
    mk_module good
    printf 'DESCRIPTION="fixture"\n' >> "$ENVUP_HOME/modules/good/meta.sh"
    ENVUP_DRY_RUN=1 run "$ENVUP_HOME/envup" install good
    [ "$status" -eq 0 ]
    [ ! -e "$ENVUP_MANIFEST" ]
}

@test "install: an install action in dependency metadata is not executed during planning" {
    mk_module a b
    mk_module b
    mkdir -p "$ENVUP_HOME/files"
    echo shared > "$ENVUP_HOME/files/config"
    printf 'safe_link files/config "$HOME/action-ran"\n' >> "$ENVUP_HOME/modules/b/meta.sh"
    run "$ENVUP_HOME/envup" install a
    [ "$status" -eq 1 ]
    [[ "$output" == *"cannot load meta.sh"* ]]
    [ ! -e "$HOME/action-ran" ]
    [ ! -e "$ENVUP_STATE_DIR/installed" ]
}

@test "--help and --version do not create a log file" {
    "$ENVUP_HOME/envup" --help  >/dev/null
    "$ENVUP_HOME/envup" --version >/dev/null
    "$ENVUP_HOME/envup" doctor --help >/dev/null
    [ ! -d "$ENVUP_STATE_DIR/logs" ]
}

# doctor and adopt both change the machine — --fix rebuilds links and drops
# manifest orphans, adopt moves content between files and runs git checkout.
# Every other command that does that leaves a record; for a long time these two
# didn't, so the one repair you later needed to explain was the unlogged one.
@test "doctor leaves a log behind" {
    run "$ENVUP_HOME/envup" doctor
    [ -d "$ENVUP_STATE_DIR/logs" ]
    run bash -c 'ls "$ENVUP_STATE_DIR"/logs/doctor_*.log'
    [ "$status" -eq 0 ]
}

@test "adopt leaves a log behind" {
    git -C "$ENVUP_HOME" init -q 2>/dev/null || skip "no git"
    run "$ENVUP_HOME/envup" adopt
    run bash -c 'ls "$ENVUP_STATE_DIR"/logs/adopt_*.log'
    [ "$status" -eq 0 ]
}

# ---- completions track the parsers --------------------------------------
#
# A completion that is missing an option is not a cosmetic gap: `envup upgrade
# --ref v0.1.0` is how you pin or roll back a release, and for as long as the
# completion didn't know the flag, the flag might as well not have existed.
# Checked against the parsers rather than against a list kept here, so an
# option added later is covered without anybody remembering to come back.

# _parser_opts <function-name> <file> — the long options a parser accepts.
_parser_opts() {
    sed -n "/^$1()/,/^}/p" "$2" |
        grep -oE '^[[:space:]]+[^)]*--[a-z][a-z-]*\)' |
        grep -oE '\-\-[a-z][a-z-]*' | sort -u
}

@test "every option a command parses is offered by the zsh completion" {
    local comp="$REPO_ROOT/completions/_envup" spec fn file opt
    for spec in "cmd_install:$REPO_ROOT/envup"    "cmd_uninstall:$REPO_ROOT/envup" \
                "cmd_upgrade:$REPO_ROOT/envup"    "cmd_status:$REPO_ROOT/envup" \
                "cmd_clean:$REPO_ROOT/envup"      "cmd_log:$REPO_ROOT/envup" \
                "_clangd_sync:$REPO_ROOT/lib/clangd.sh" \
                "doctor_main:$REPO_ROOT/lib/doctor.sh" \
                "adopt_main:$REPO_ROOT/lib/adopt.sh"; do
        fn="${spec%%:*}"; file="${spec#*:}"
        while read -r opt; do
            [[ -n "$opt" ]] || continue
            # '*' prefixes a repeatable option in an _arguments spec.
            grep -qE -- "'\*?$opt\[" "$comp" || {
                echo "$fn accepts $opt but completions/_envup never offers it"
                return 1
            }
        done < <(_parser_opts "$fn" "$file")
    done
}
@test "logs are written under ENVUP_STATE_DIR, not a hardcoded \$HOME path" {
    "$ENVUP_HOME/envup" doctor >/dev/null 2>&1 || true
    [ -d "$ENVUP_STATE_DIR/logs" ]
    [ ! -d "$HOME/.local/state/envup/logs" ]
}
