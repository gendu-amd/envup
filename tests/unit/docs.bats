#!/usr/bin/env bats
# The documentation, checked against the repo it describes.
#
# Docs drift silently. Nothing fails, nothing warns, and the first person to
# notice is someone following an instruction that stopped working — which is
# exactly the reader you can least afford to lose. Three things here are
# mechanically checkable, so they are checked:
#
#   1. Every relative link resolves. A file moved into docs/history/ takes its
#      inbound links with it, and a README pointing at a 404 is worse than one
#      that says nothing.
#   2. The two READMEs document the same environment variables. They are
#      allowed to differ in depth — the Chinese one is not a line-by-line
#      translation — but a knob that exists in one and not the other means a
#      reader of the wrong language cannot find it at all.
#   3. Every path the docs name in backticks exists. This is where the rot
#      actually shows up: `modules/*/install.sh` outlived the v1 contract by
#      two releases in prose alone.
#
# Deliberately not checked: prose accuracy. That needs a human.

load '../test_helper'

setup() { REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"; }

# The docs that describe the *current* repo. docs/history/ is excluded on
# purpose: those files are frozen records of a layout that no longer exists,
# and holding them to the present tree would mean either editing history or
# living with a permanently red test.
_current_docs() {
    printf '%s\n' \
        "$REPO_ROOT/README.md" "$REPO_ROOT/README.zh-CN.md" \
        "$REPO_ROOT/CONTRIBUTING.md" "$REPO_ROOT/CHANGELOG.md" \
        "$REPO_ROOT/docs/ARCHITECTURE.md" "$REPO_ROOT/docs/TMUX.md" \
        "$REPO_ROOT/docs/CLIPBOARD.md"
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

# The history directory has its own index, and an unlinked archive is a
# directory nobody opens. Both READMEs have to point at it.
@test "the archived docs are reachable from both READMEs" {
    [[ -f "$REPO_ROOT/docs/history/README.md" ]]
    grep -q 'docs/history' "$REPO_ROOT/README.md"
    grep -q 'docs/history' "$REPO_ROOT/README.zh-CN.md"
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

# Only paths that look like repo paths — a leading directory that exists here.
# `~/.zshrc` and `apt-get install` are also inside backticks and are not files.
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
