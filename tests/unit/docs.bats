#!/usr/bin/env bats
# Mechanical checks for links, documented variables, and named repo paths.

load '../test_helper'

setup() { REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"; }

_current_docs() {
    printf '%s\n' \
        "$REPO_ROOT/README.md" "$REPO_ROOT/README.zh-CN.md" \
        "$REPO_ROOT/CONTRIBUTING.md" "$REPO_ROOT/CHANGELOG.md" \
        "$REPO_ROOT/docs/guide.md"
}

@test "every relative link in the docs resolves" {
    local f dir target raw bad=""
    while read -r f; do
        dir="$(dirname "$f")"
        while read -r raw; do
            target="${raw%%#*}"                       # drop the anchor
            [[ -n "$target" ]] || continue            # a bare #anchor is fine
            [[ "$target" == http* || "$target" == mailto:* ]] && continue
            if [[ ! -e "$dir/$target" ]]; then
                bad+="  ${f#$REPO_ROOT/} -> $raw"$'\n'
            elif [[ "$raw" == *guide.md#* ]]; then
                awk '/^#+ / { sub(/^#+ /, ""); print tolower($0) }' "$dir/$target" |
                    sed 's/[^a-z0-9 -]//g; s/ /-/g' | grep -qxF "${raw#*#}" ||
                    bad+="  ${f#$REPO_ROOT/} -> $raw"$'\n'
            fi
        done < <(grep -oE '\]\([^)]+\)' "$f" | sed 's/^](//; s/)$//')
    done < <(_current_docs)
    [[ -z "$bad" ]] || { echo "dead links:"; echo "$bad"; return 1; }
}

@test "the guide provides the core configuration variable table" {
    local name
    for name in ENVUP_DRY_RUN ENVUP_OFFLINE ENVUP_LOCAL_BIN ENVUP_STATE_DIR \
                ENVUP_NET_TIMEOUT ENVUP_NVIM_LAZY ENVUP_PROJECT_DIRS; do
        grep -qF "| \`$name\` |" "$REPO_ROOT/docs/guide.md" || {
            echo "missing guide entry: $name"; return 1
        }
    done
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
