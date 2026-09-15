#!/usr/bin/env bats

load '../test_helper'

setup() {
    common_setup
    PROJECT="$TEST_TMP/host tree/project"
    TOOLCHAIN="$TEST_TMP/toolchains/rocm-current"
    mkdir -p "$PROJECT/build" "$PROJECT/src" "$TOOLCHAIN/bin" "$TOOLCHAIN/lib/llvm/bin"
    git -C "$PROJECT" init -q
    printf 'int main() { return 0; }\n' >"$PROJECT/src/main.cpp"
    for tool in hipcc clang clang++; do
        local path="$TOOLCHAIN/bin/$tool"
        [[ "$tool" == clang* ]] && path="$TOOLCHAIN/lib/llvm/bin/$tool"
        printf '#!/bin/sh\necho clang version 23.0.0\n' >"$path"
        chmod +x "$path"
    done
    cat >"$PROJECT/.clangd" <<'EOF'
CompileFlags:
  CompilationDatabase: build
EOF
    cat >"$PROJECT/build/CMakeCache.txt" <<'EOF'
CMAKE_HOME_DIRECTORY:INTERNAL=/mnt/workspace/user
CMAKE_C_COMPILER:FILEPATH=/mnt/workspace/user/toolchain/lib/llvm/bin/clang
CMAKE_CXX_COMPILER:FILEPATH=/mnt/workspace/user/toolchain/bin/hipcc
CMAKE_HIP_COMPILER:FILEPATH=/mnt/workspace/user/toolchain/lib/llvm/bin/clang++
EOF
    cat >"$PROJECT/build/compile_commands.json" <<'EOF'
[
  {
    "directory": "/mnt/workspace/user/build",
    "command": "/mnt/workspace/user/toolchain/bin/hipcc -I/mnt/workspace/user/src -c /mnt/workspace/user/src/main.cpp",
    "file": "/mnt/workspace/user/src/main.cpp"
  }
]
EOF

    export PROJECT TOOLCHAIN
    stub_bin docker <<'EOF'
#!/bin/bash
case "$1" in
    ps) printf '%s\n' aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa ;;
    inspect)
        printf 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\t/task-one\t2000-01-01T00:00:00Z\t%s\t/mnt/workspace/user\n' "$PROJECT"
        printf 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\t/task-one\t2000-01-01T00:00:00Z\t%s\t/mnt/workspace/user/toolchain\n' "$TOOLCHAIN"
        ;;
    *) exit 2 ;;
esac
EOF
}

teardown() { common_teardown; }

@test "clangd sync discovers arbitrary host and container paths from Docker mounts" {
    run "$REPO_ROOT/envup" clangd sync "$PROJECT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"clangd database synced"* ]]

    local index="$HOME/.cache/nvim/envup/clangd/index.tsv" database
    [ -f "$index" ]
    database="$(awk -F '\t' -v root="$PROJECT" '$1 == root { print $2 }' "$index")"
    [ -f "$database" ]
    grep -Fq "$PROJECT/src/main.cpp" "$database"
    grep -Fq "$TOOLCHAIN/bin/hipcc" "$database"
    ! grep -Fq "$PROJECT/toolchain" "$database"
    ! grep -Fq '/mnt/workspace/user' "$database"

    # The Docker-owned database remains byte-for-byte in its own namespace.
    grep -Fq '/mnt/workspace/user/toolchain/bin/hipcc' "$PROJECT/build/compile_commands.json"
}

@test "clangd status and clean use the project cache without Docker" {
    "$REPO_ROOT/envup" clangd sync "$PROJECT" >/dev/null
    rm "$STUB_BIN/docker"

    run "$REPO_ROOT/envup" clangd status "$PROJECT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"task-one"* ]]

    run "$REPO_ROOT/envup" clangd clean "$PROJECT"
    [ "$status" -eq 0 ]
    run "$REPO_ROOT/envup" clangd status "$PROJECT"
    [ "$status" -ne 0 ]
}

@test "clangd status detects a Docker database regenerated after sync" {
    "$REPO_ROOT/envup" clangd sync "$PROJECT" >/dev/null
    touch -t 203001010000 "$PROJECT/build/compile_commands.json"

    run "$REPO_ROOT/envup" clangd status "$PROJECT"
    [ "$status" -ne 0 ]
    [[ "$output" == *"changed after the last sync"* ]]
}

@test "clangd sync refuses to guess between genuinely different containers" {
    stub_bin docker <<'EOF'
#!/bin/bash
case "$1" in
    ps) printf '%s\n' aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb ;;
    inspect)
        printf 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\t/task-one\t2000-01-01T00:00:00Z\t%s\t/mnt/workspace/user\n' "$PROJECT"
        printf 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\t/task-one\t2000-01-01T00:00:00Z\t%s\t/mnt/workspace/user/toolchain\n' "$TOOLCHAIN"
        printf 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\t/task-two\t2000-01-01T00:00:00Z\t%s\t/mnt/workspace/user\n' "$PROJECT"
        printf 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\t/task-two\t2000-01-01T00:00:00Z\t%s/other\t/mnt/workspace/user/toolchain\n' "$TOOLCHAIN"
        ;;
esac
EOF
    mkdir -p "$TOOLCHAIN/other/bin" "$TOOLCHAIN/other/lib/llvm/bin"
    cp "$TOOLCHAIN/bin/hipcc" "$TOOLCHAIN/other/bin/hipcc"
    cp "$TOOLCHAIN/lib/llvm/bin/clang" "$TOOLCHAIN/other/lib/llvm/bin/clang"
    cp "$TOOLCHAIN/lib/llvm/bin/clang++" "$TOOLCHAIN/other/lib/llvm/bin/clang++"

    run "$REPO_ROOT/envup" clangd sync "$PROJECT"
    [ "$status" -ne 0 ]
    [[ "$output" == *"more than one Docker environment"* ]]

    run "$REPO_ROOT/envup" clangd sync --container task-two "$PROJECT"
    [ "$status" -eq 0 ]
    local database
    database="$(awk -F '\t' -v root="$PROJECT" '$1 == root { print $2 }' "$HOME/.cache/nvim/envup/clangd/index.tsv")"
    grep -Fq "$TOOLCHAIN/other/bin/hipcc" "$database"
}

@test "clangd sync identifies the task container created with the database" {
    stub_bin docker <<'EOF'
#!/bin/bash
case "$1" in
    ps) printf '%s\n' aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb ;;
    inspect)
        now="$(date -u +%Y-%m-%dT%H:%M):00Z"
        printf 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\t/old-task\t2000-01-01T00:00:00Z\t%s\t/mnt/workspace/user\n' "$PROJECT"
        printf 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\t/current-task\t%s\t%s\t/mnt/workspace/user\n' "$now" "$PROJECT"
        printf 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\t/current-task\t%s\t%s\t/mnt/workspace/user/toolchain\n' "$now" "$TOOLCHAIN"
        ;;
esac
EOF

    run "$REPO_ROOT/envup" clangd sync "$PROJECT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"current-task"* ]]
}
