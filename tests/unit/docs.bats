#!/usr/bin/env bats
# Mechanical checks for links, documented variables, and named repo paths.

load '../test_helper'

setup() { REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"; }

_current_docs() {
    printf '%s\n' \
        "$REPO_ROOT/README.md" "$REPO_ROOT/README.zh-CN.md" \
        "$REPO_ROOT/CONTRIBUTING.md" "$REPO_ROOT/CHANGELOG.md"
}

@test "every relative link in the docs resolves" {
    local f dir target raw bad=""
    while read -r f; do
        dir="$(dirname "$f")"
        while read -r raw; do
            target="${raw%%#*}"                       # drop the anchor
            [[ -n "$target" ]] || continue            # a bare #anchor is fine
            [[ "$target" == http* || "$target" == mailto:* ]] && continue
            [[ -e "$dir/$target" ]] || bad+="  ${f#$REPO_ROOT/} -> $raw"$'\n'
        done < <(grep -oE '\]\([^)]+\)' "$f" | sed 's/^](//; s/)$//')
    done < <(_current_docs)
    [[ -z "$bad" ]] || { echo "dead links:"; echo "$bad"; return 1; }
}

@test "both READMEs document the same environment variables" {
    local only
    only="$(comm -3 \
        <(grep -oE '^\| `ENVUP_[A-Z_]+`' "$REPO_ROOT/README.md"       | tr -d '|` ' | sort) \
        <(grep -oE '^\| `ENVUP_[A-Z_]+`' "$REPO_ROOT/README.zh-CN.md" | tr -d '|` ' | sort))"
    [[ -z "$only" ]] || {
        echo "documented in one README but not the other (left=en, right=zh):"
        echo "$only"; return 1
    }
}

# Only path-like code spans rooted at a repository directory are checked.
@test "every repo path the docs name actually exists" {
    local f p bad=""
    while read -r f; do
        while read -r p; do
            p="${p%/}"
            [[ "$p" == *'*'* || "$p" == *'<'* ]] && continue   # a glob or a placeholder
            [[ -e "$REPO_ROOT/$p" ]] || bad+="  ${f#$REPO_ROOT/}: $p"$'\n'
        done < <(grep -oE '`(lib|modules|profiles|tests|scripts|docs|completions)/[A-Za-z0-9_./*<>-]+`' "$f" |
                 tr -d '`' | sort -u)
    done < <(_current_docs)
    [[ -z "$bad" ]] || { echo "paths named in the docs that do not exist:"; echo "$bad"; return 1; }
}
