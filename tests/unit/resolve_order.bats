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

@test "resolve_order: a dependency cycle terminates (no hang)" {
    run timeout 10 bash -c "source '$REPO_ROOT/lib.sh'; ENVUP_HOME='$ENVUP_HOME' resolve_order cyc1"
    [ "$status" -eq 0 ]
    [[ "$output" == *cyc1* ]]
    [[ "$output" == *cyc2* ]]
}

@test "resolve_order: unknown modules are skipped" {
    run resolve_order nope
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
