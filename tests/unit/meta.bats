#!/usr/bin/env bats
# module_meta / module_deps read fields (scalar + array) from a module meta.sh.

load '../test_helper'

setup() {
    common_setup
    mkdir -p "$ENVUP_HOME/modules/demo"
    cat > "$ENVUP_HOME/modules/demo/meta.sh" <<'EOF'
#!/bin/bash
NAME="demo"
DESCRIPTION="a demo module"
DEPENDS=(zsh git)
EOF
}
teardown() { common_teardown; }

@test "module_meta: reads a scalar field" {
    run module_meta demo DESCRIPTION
    [ "$output" = "a demo module" ]
}

@test "module_meta: reads an array field (one value per line)" {
    run module_meta demo DEPENDS
    [ "$output" = "zsh
git" ]
}

@test "module_deps: lists dependencies" {
    run module_deps demo
    [ "$output" = "zsh
git" ]
}

@test "module_exists: true for present, false for absent" {
    run module_exists demo;    [ "$status" -eq 0 ]
    run module_exists missing; [ "$status" -ne 0 ]
}
