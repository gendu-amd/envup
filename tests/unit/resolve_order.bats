#!/usr/bin/env bats
# I5 — dependency resolution: DEPENDS before dependents, deduped, cycle-safe.

load '../test_helper'

setup() {
    common_setup
    mk_module a
    mk_module b a
    mk_module c b
    mk_module cyc1 cyc2
    mk_module cyc2 cyc1
}
teardown() { common_teardown; }

@test "resolve_order: single module resolves to itself" {
    run resolve_order a
    [ "$status" -eq 0 ]
    [ "$output" = "a" ]
}

@test "resolve_order: dependencies come before the dependent" {
    run resolve_order c
    [ "$status" -eq 0 ]
    [ "$output" = "a
b
c" ]
}

@test "resolve_order: duplicates are collapsed" {
    run resolve_order c c a
    [ "$status" -eq 0 ]
    [ "$output" = "a
b
c" ]
}

@test "resolve_order: a dependency cycle fails without emitting a partial plan" {
    run timeout 10 bash -c "source '$REPO_ROOT/lib.sh'; ENVUP_HOME='$ENVUP_HOME' resolve_order cyc1"
    [ "$status" -eq 1 ]
    [[ "$output" == *"dependency cycle"* ]]
    [[ "$output" != *$'\ncyc1'* && "$output" != *$'\ncyc2'* ]]
}

@test "resolve_order: unknown modules fail" {
    run resolve_order nope
    [ "$status" -eq 1 ]
    [[ "$output" == *"no such dependency module"* ]]
}

@test "resolve_order: a missing transitive dependency fails the whole plan" {
    mk_module a missing
    run resolve_order c
    [ "$status" -eq 1 ]
    [[ "$output" == *missing* ]]
    [[ "$output" != *$'\nc\n'* ]]
}

@test "resolve_order: a failed metadata load cannot become an empty dependency list" {
    echo 'return 1' >> "$ENVUP_HOME/modules/a/meta.sh"
    run resolve_order c
    [ "$status" -eq 1 ]
    [[ "$output" == *"cannot load meta.sh"* ]]
}

@test "resolve_order: module names cannot traverse outside the module directory" {
    run resolve_order ..
    [ "$status" -eq 1 ]
}
