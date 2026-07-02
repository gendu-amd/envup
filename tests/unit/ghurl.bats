#!/usr/bin/env bats
# gh_url: GitHub mirror/proxy prefix (ENVUP_GH_MIRROR). Unset = no change.

load '../test_helper'

setup() { common_setup; }
teardown() { common_teardown; }

@test "gh_url: returns the URL unchanged when no mirror is set" {
    run gh_url "https://github.com/x/y.git"
    [ "$status" -eq 0 ]
    [ "$output" = "https://github.com/x/y.git" ]
}

@test "gh_url: prefixes the mirror when ENVUP_GH_MIRROR is set" {
    ENVUP_GH_MIRROR=https://ghproxy.com run gh_url "https://github.com/x/y.git"
    [ "$output" = "https://ghproxy.com/https://github.com/x/y.git" ]
}

@test "gh_url: normalizes a trailing slash on the mirror" {
    ENVUP_GH_MIRROR=https://ghproxy.com/ run gh_url "https://raw.githubusercontent.com/a/b"
    [ "$output" = "https://ghproxy.com/https://raw.githubusercontent.com/a/b" ]
}
