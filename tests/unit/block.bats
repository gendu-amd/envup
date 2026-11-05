#!/usr/bin/env bats
# Managed text block: idempotent insert/replace/remove in a file we don't own.

load '../test_helper'

setup() {
    common_setup
    TARGET="$HOME/.bashrc"
    printf 'line1\nline2\n' > "$TARGET"
}
teardown() { common_teardown; }

@test "block_set: inserts a marked block" {
    echo "hello" | block_set "$TARGET" demo
    run grep -c '>>> envup:demo >>>' "$TARGET"
    [ "$output" = "1" ]
    run grep -q "hello" "$TARGET"
    [ "$status" -eq 0 ]
}

@test "block_set: re-setting replaces content without duplicating markers" {
    echo "first"  | block_set "$TARGET" demo
    echo "second" | block_set "$TARGET" demo
    run grep -c '>>> envup:demo >>>' "$TARGET"
    [ "$output" = "1" ]
    run grep -q "second" "$TARGET"; [ "$status" -eq 0 ]
    run grep -q "first"  "$TARGET"; [ "$status" -ne 0 ]
}

@test "block_del: removes the block and leaves the rest intact" {
    echo "hello" | block_set "$TARGET" demo
    block_del "$TARGET" demo
    run grep -q 'envup:demo' "$TARGET"; [ "$status" -ne 0 ]
    run grep -q 'line1' "$TARGET";      [ "$status" -eq 0 ]
}

@test "block_set: dry-run makes no change (I4)" {
    before="$(cat "$TARGET")"
    echo "hello" | ENVUP_DRY_RUN=1 block_set "$TARGET" demo
    [ "$(cat "$TARGET")" = "$before" ]
}

@test "managed blocks preserve rc symlinks and their shared targets" {
    local shared="$ENVUP_HOME/shared-rc"
    mv "$TARGET" "$shared"
    ln -s "$shared" "$TARGET"
    run block_set "$TARGET" demo <<<hello
    [ "$status" -eq 1 ]
    [ -L "$TARGET" ]
    [ "$(cat "$shared")" = $'line1\nline2' ]
    printf '# >>> envup:demo >>>\nhello\n# <<< envup:demo <<<\n' >> "$shared"
    cp "$shared" "$TEST_TMP/before"
    run block_del "$TARGET" demo
    [ "$status" -eq 1 ]
    [ -L "$TARGET" ]
    cmp "$shared" "$TEST_TMP/before"
}

@test "managed blocks never create the target of a dangling rc symlink" {
    rm "$TARGET"
    ln -s "$ENVUP_HOME/missing-rc" "$TARGET"
    run block_set "$TARGET" demo <<<hello
    [ "$status" -eq 1 ]
    run block_del "$TARGET" demo
    [ "$status" -eq 1 ]
    [ -L "$TARGET" ]
    [ ! -e "$ENVUP_HOME/missing-rc" ]
    [ ! -e "$ENVUP_STATE_DIR/created" ]
}

@test "block_set stops if reading or removing the old block fails" {
    block_set "$TARGET" demo <<<first
    cp "$TARGET" "$TEST_TMP/before"
    stub_bin sed <<'EOF'
#!/bin/bash
exit 1
EOF
    run block_set "$TARGET" demo <<<second
    [ "$status" -eq 1 ]
    cmp "$TARGET" "$TEST_TMP/before"
    rm "$STUB_BIN/sed"
    stub_bin grep <<'EOF'
#!/bin/bash
exit 2
EOF
    hash -r
    run block_set "$TARGET" demo <<<second
    [ "$status" -eq 1 ]
    cmp "$TARGET" "$TEST_TMP/before"
}

@test "block_set stops if the creation ledger cannot be written" {
    rm "$TARGET"
    mkdir -p "$ENVUP_STATE_DIR/created"
    run block_set "$TARGET" demo <<<hello
    [ "$status" -eq 1 ]
    [ ! -s "$TARGET" ]
}

@test "replacing a block retains ownership of a file created by envup" {
    rm "$TARGET"
    block_set "$TARGET" demo <<<first
    block_set "$TARGET" demo <<<second
    block_del "$TARGET" demo
    [ ! -e "$TARGET" ]
}

@test "removing a block preserves a pre-existing empty rc file" {
    : > "$TARGET"
    block_set "$TARGET" demo <<<hello
    block_del "$TARGET" demo
    [ -f "$TARGET" ]
    [ ! -s "$TARGET" ]
}

@test "block_del reports backup removal failure and retains the backup" {
    block_set "$TARGET" demo <<<hello
    export BLOCK_TEST_RM="$(command -v rm)"
    stub_bin rm <<'EOF'
#!/bin/bash
[[ "${@: -1}" == *.envup-bak ]] && exit 1
exec "$BLOCK_TEST_RM" "$@"
EOF
    hash -r
    run block_del "$TARGET" demo
    [ "$status" -eq 1 ]
    [ -f "$TARGET.envup-bak" ]
    grep -q hello "$TARGET.envup-bak"
}

@test "block_del keeps the creation record when reclaiming the empty rc fails" {
    rm "$TARGET"
    block_set "$TARGET" demo <<<hello
    export BLOCK_TEST_RM="$(command -v rm)"
    stub_bin rm <<'EOF'
#!/bin/bash
[[ "${@: -1}" == "$HOME/.bashrc" ]] && exit 1
exec "$BLOCK_TEST_RM" "$@"
EOF
    hash -r
    run block_del "$TARGET" demo
    [ "$status" -eq 1 ]
    [ -f "$TARGET" ]
    grep -qxF "$TARGET" "$ENVUP_STATE_DIR/created"
    run block_del "$TARGET" demo
    [ "$status" -eq 1 ]
    rm "$STUB_BIN/rm"
    hash -r
    block_del "$TARGET" demo
    [ ! -e "$TARGET" ]
}

@test "block_set preserves the old content if reading its new input fails" {
    stub_bin cat <<'EOF'
#!/bin/bash
exit 1
EOF
    hash -r
    run block_set "$TARGET" demo <<<hello
    [ "$status" -eq 1 ]
    [ "$(sed -n '1p' "$TARGET")" = line1 ]
    [ "$(wc -l < "$TARGET")" -eq 2 ]
}

zsh_hook_fixture() {
    mk_module zsh
    cp "$REPO_ROOT/modules/zsh/hooks.sh" "$ENVUP_HOME/modules/zsh/hooks.sh"
    printf '\npre_install() { return 0; }\n' >> "$ENVUP_HOME/modules/zsh/hooks.sh"
    stub_bin zsh <<'EOF'
#!/bin/bash
echo 'zsh 5.9'
EOF
    export ENVUP_PRIV=none SHELL=/bin/bash
}

@test "zsh install propagates shim refusal without claiming success" {
    zsh_hook_fixture
    mv "$TARGET" "$ENVUP_HOME/shared-rc"
    ln -s "$ENVUP_HOME/shared-rc" "$TARGET"
    run engine_install zsh
    [ "$status" -eq 1 ]
    [[ "$output" != *'shim installed'* ]]
    [[ "$output" == *'post_install failed'* ]]
    ! manifest_has zsh
    [ -L "$TARGET" ]
    [ "$(cat "$ENVUP_HOME/shared-rc")" = $'line1\nline2' ]
}

@test "zsh uninstall propagates shim removal failure and retains ownership record" {
    zsh_hook_fixture
    block_set "$TARGET" zsh-default <<<hello
    manifest_add zsh
    stub_bin sed <<'EOF'
#!/bin/bash
exit 1
EOF
    run engine_uninstall zsh
    [ "$status" -eq 1 ]
    [[ "$output" != *'removed the bash->zsh shim'* ]]
    manifest_has zsh
    grep -q hello "$TARGET"
}
