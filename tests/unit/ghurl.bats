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

@test "gh_url: rewrites every GitHub host the providers actually reach" {
    local h
    for h in github.com raw.githubusercontent.com api.github.com \
             objects.githubusercontent.com codeload.github.com; do
        ENVUP_GH_MIRROR=https://m run gh_url "https://$h/a/b"
        [ "$output" = "https://m/https://$h/a/b" ] || {
            echo "not rewritten: $h -> $output"; return 1
        }
    done
}

# A GitHub proxy cannot serve setup.atuin.sh. Prefixing it produced
# https://m/https://setup.atuin.sh, which 404s on exactly the machines that
# set a mirror because they can't reach GitHub directly.
@test "gh_url: leaves a non-GitHub vendor URL alone even with a mirror set" {
    ENVUP_GH_MIRROR=https://m run gh_url "https://setup.atuin.sh"
    [ "$output" = "https://setup.atuin.sh" ]
}

@test "gh_url: is not fooled by a lookalike host" {
    local u
    for u in https://github.com.evil.example/x/y \
             https://notgithub.com/x/y \
             https://mygithub.com/x/y; do
        ENVUP_GH_MIRROR=https://m run gh_url "$u"
        [ "$output" = "$u" ] || { echo "wrongly rewritten: $u -> $output"; return 1; }
    done
}

@test "gh_url: leaves ssh remotes alone — a proxy prefix cannot carry them" {
    ENVUP_GH_MIRROR=https://m run gh_url "git@github.com:x/y.git"
    [ "$output" = "git@github.com:x/y.git" ]
}

# The URLs the shipped modules hand to net_fetch/net_clone, checked against the
# rule rather than against a copy of it: whatever a module declares, a mirror
# must only ever be prefixed onto a host the mirror can serve.
@test "gh_url: no shipped module URL is rewritten to an unreachable host" {
    local f url out
    for f in "$ENVUP_HOME"/modules/*/meta.sh; do
        while read -r url; do
            [[ -n "$url" ]] || continue
            out="$(ENVUP_GH_MIRROR=https://m gh_url "$url")"
            [[ "$out" == "$url" || "$out" =~ ^https://m/https://(github|raw\.githubusercontent|api\.github|objects\.githubusercontent|codeload\.github)\.com/ ]] || {
                echo "$f: $url -> $out"; return 1
            }
        done < <(grep -oE 'https?://[A-Za-z0-9._~:/?#@!$&*+,;=%-]+' "$f" || true)
    done
}
