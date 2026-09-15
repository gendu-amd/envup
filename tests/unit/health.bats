#!/usr/bin/env bats
# Machine-state inspection (lib/health.sh). The question this layer exists to
# answer is "is what the manifest claims still true?" — because for two versions
# it wasn't asked, and `status` printed a green tick next to a module whose
# config the user had deleted by hand.

load '../test_helper'

setup() {
    common_setup
    mkdir -p "$ENVUP_HOME/files"
    echo hello > "$ENVUP_HOME/files/thing"
}
teardown() { common_teardown; }

mk_meta() {
    local n="$1"; shift
    mkdir -p "$ENVUP_HOME/modules/$n"
    printf '#!/bin/bash\nNAME="%s"\nDESCRIPTION="fixture"\n%s\n' "$n" "$*" \
        > "$ENVUP_HOME/modules/$n/meta.sh"
}

# ---- one link ------------------------------------------------------------

@test "health_link_state: a correct link is ok" {
    ln -s "$ENVUP_HOME/files/thing" "$HOME/.thing"
    run health_link_state files/thing "$HOME/.thing"
    [ "$output" = "ok" ]
}

@test "health_link_state: nothing there is missing" {
    run health_link_state files/thing "$HOME/.thing"
    [ "$output" = "missing" ]
}

@test "health_link_state: a link into the repo whose source is gone is broken" {
    ln -s "$ENVUP_HOME/files/thing" "$HOME/.thing"
    rm -f "$ENVUP_HOME/files/thing"
    run health_link_state files/thing "$HOME/.thing"
    [ "$output" = "broken" ]
}

@test "health_link_state: a link into the repo pointing at the wrong file is broken" {
    echo other > "$ENVUP_HOME/files/other"
    ln -s "$ENVUP_HOME/files/other" "$HOME/.thing"
    run health_link_state files/thing "$HOME/.thing"
    [ "$output" = "broken" ]
}

@test "health_link_state: the user's own file is foreign, never ours to assume" {
    echo "mine" > "$HOME/.thing"
    run health_link_state files/thing "$HOME/.thing"
    [ "$output" = "foreign" ]
}

@test "health_link_state: a link somewhere outside the repo is foreign" {
    echo elsewhere > "$TEST_TMP/elsewhere"
    ln -s "$TEST_TMP/elsewhere" "$HOME/.thing"
    run health_link_state files/thing "$HOME/.thing"
    [ "$output" = "foreign" ]
}

# ---- one module ----------------------------------------------------------

@test "health_probe: a module that is not in the manifest is absent" {
    mk_meta cfg 'LINKS=("files/thing:$HOME/.thing")'
    run health_probe cfg
    [[ "$output" == *$'state\tabsent'* ]]
}

@test "health_probe: installed and linked reads ok" {
    mk_meta cfg 'LINKS=("files/thing:$HOME/.thing")'
    ln -s "$ENVUP_HOME/files/thing" "$HOME/.thing"
    manifest_add cfg
    run health_probe cfg
    [[ "$output" == *$'state\tok'* ]]
}

@test "health_probe: deleting the config by hand makes it broken, not ok" {
    # The whole reason this file exists. `status` used to read the manifest and
    # nothing else, so this machine reported a clean install.
    mk_meta cfg 'LINKS=("files/thing:$HOME/.thing")'
    ln -s "$ENVUP_HOME/files/thing" "$HOME/.thing"
    manifest_add cfg
    rm -f "$HOME/.thing"

    run health_probe cfg
    [[ "$output" == *$'state\tbroken'* ]]
    [[ "$output" == *$'link\tmissing'* ]]
}

@test "health_probe: config linked but the tool missing is degraded, not broken" {
    # The designed outcome on a server without root: the config is correct and
    # the module starts working the day someone installs the package.
    mk_meta srv 'VERIFY_BIN="definitely-not-a-real-binary"
LINKS=("files/thing:$HOME/.thing")'
    ln -s "$ENVUP_HOME/files/thing" "$HOME/.thing"
    manifest_add srv
    run health_probe srv
    [[ "$output" == *$'state\tdegraded'* ]]
    [[ "$output" == *$'tool\tmissing'* ]]
}

@test "health_probe: a tool older than the floor reads as old" {
    stub_bin oldtool <<'EOF'
#!/bin/bash
echo "oldtool 0.9.5"
EOF
    mk_meta ot 'VERIFY_BIN="oldtool"
VERIFY_MIN_VERSION="0.10.0"'
    manifest_add ot
    run health_probe ot
    [[ "$output" == *$'tool\told'* ]]
    [[ "$output" == *"0.9.5"* ]]
}

@test "health_probe: a binary that cannot run reads as broken, never as ok" {
    # The real one: a prebuilt nvim wanting glibc 2.33 on a host with 2.32 dies
    # on every call. health used to scrape the "GLIBC_2.33 not found" message
    # for a dotted number, report version 2.33, and print a green tick for a
    # tool that could not start.
    stub_bin wontrun <<'EOF'
#!/bin/bash
echo "wontrun: /lib64/libc.so.6: version \`GLIBC_2.33' not found" >&2
exit 1
EOF
    mk_meta wr 'VERIFY_BIN="wontrun"'
    manifest_add wr
    run health_probe wr
    [[ "$output" == *$'tool\tbroken'* ]]
    [[ "$output" != *$'tool\tok'* ]]
    [[ "$output" != *"2.33"* ]]
    # Config is still linked, so the module is degraded rather than broken —
    # doctor is what escalates this one to an issue.
    [[ "$output" == *$'state\tdegraded'* ]]
}

@test "health_probe: an optional link whose source was never checked out is not a fault" {
    mk_meta sub 'LINKS=("?files/never-cloned:$HOME/.sub")'
    manifest_add sub
    run health_probe sub
    [[ "$output" == *$'link\tskipped'* ]]
    [[ "$output" == *$'state\tok'* ]]
}

@test "health_probe: one module's meta does not leak into the next" {
    # Probing runs meta.sh. Without the subshell, VERIFY_BIN from the module
    # before would still be set and every later module would be judged by it.
    mk_meta withbin 'VERIFY_BIN="definitely-not-a-real-binary"'
    mk_meta nobin   'LINKS=("files/thing:$HOME/.thing")'
    ln -s "$ENVUP_HOME/files/thing" "$HOME/.thing"
    manifest_add withbin; manifest_add nobin

    health_probe withbin >/dev/null
    run health_probe nobin
    [[ "$output" == *$'tool\tnone'* ]]
    [[ "$output" == *$'state\tok'* ]]
}

@test "health_field / health_records: read the probe without re-running it" {
    mk_meta cfg 'LINKS=("files/thing:$HOME/.thing")'
    ln -s "$ENVUP_HOME/files/thing" "$HOME/.thing"
    manifest_add cfg
    probe="$(health_probe cfg)"
    run health_field "$probe" state
    [ "$output" = "ok" ]
    run health_records "$probe" link
    [[ "$output" == ok* ]]
}

# ---- saying which kind of link problem it is -----------------------------
#
# All three states used to be printed as "N broken link(s)". The common one is
# a link the repo grew since this machine last installed — nothing is damaged,
# `envup install` creates it — and calling that "broken" sent a real user
# looking for damage that was not there.

@test "health_link_summary: a link the repo added and nobody has created yet" {
    mk_meta cfg 'LINKS=("files/thing:$HOME/.thing" "files/other:$HOME/.other")'
    ln -s "$ENVUP_HOME/files/thing" "$HOME/.thing"
    manifest_add cfg
    run health_link_summary "$(health_probe cfg)"
    [ "$output" = "1 link not created yet" ]
}

@test "health_link_summary: counts read as English, singular and plural" {
    mk_meta cfg 'LINKS=("files/a:$HOME/.a" "files/b:$HOME/.b" "files/c:$HOME/.c")'
    manifest_add cfg
    run health_link_summary "$(health_probe cfg)"
    [ "$output" = "3 links not created yet" ]
}

@test "health_link_summary: a dangling link is not the same sentence" {
    mk_meta cfg 'LINKS=("files/thing:$HOME/.thing")'
    ln -s "$ENVUP_HOME/files/gone" "$HOME/.thing"     # ours, source absent
    manifest_add cfg
    run health_link_summary "$(health_probe cfg)"
    [ "$output" = "1 dangling link" ]
}

@test "health_link_summary: your own file in the way says so" {
    mk_meta cfg 'LINKS=("files/thing:$HOME/.thing")'
    printf 'mine\n' > "$HOME/.thing"
    manifest_add cfg
    run health_link_summary "$(health_probe cfg)"
    [ "$output" = "1 path already in use" ]
}

@test "health_link_summary: mixed problems are listed, not merged" {
    mk_meta cfg 'LINKS=("files/a:$HOME/.a" "files/b:$HOME/.b")'
    printf 'mine\n' > "$HOME/.b"
    manifest_add cfg
    run health_link_summary "$(health_probe cfg)"
    [ "$output" = "1 link not created yet, 1 path already in use" ]
}

@test "health_link_counts: the numbers status --json prints" {
    mk_meta cfg 'LINKS=("files/a:$HOME/.a" "files/b:$HOME/.b" "files/c:$HOME/.c")'
    ln -s "$ENVUP_HOME/files/gone" "$HOME/.a"
    printf 'mine\n' > "$HOME/.c"
    manifest_add cfg
    run health_link_counts "$(health_probe cfg)"
    [ "$output" = "1 1 1" ]        # not-created-yet, dangling, in-the-way
}

@test "health_link_counts: a healthy module counts nothing" {
    mk_meta cfg 'LINKS=("files/thing:$HOME/.thing")'
    ln -s "$ENVUP_HOME/files/thing" "$HOME/.thing"
    manifest_add cfg
    run health_link_counts "$(health_probe cfg)"
    [ "$output" = "0 0 0" ]
}

# ---- drift ---------------------------------------------------------------

git_repo() {
    git -C "$ENVUP_HOME" init -q
    git -C "$ENVUP_HOME" config user.email t@example.com
    git -C "$ENVUP_HOME" config user.name  t
    mkdir -p "$ENVUP_HOME/modules/zsh/files"
    printf 'line one\nline two\n' > "$ENVUP_HOME/modules/zsh/files/.zshrc"
    git -C "$ENVUP_HOME" add -A
    git -C "$ENVUP_HOME" commit -qm init
}

@test "health_drift: a clean checkout reports nothing" {
    git_repo
    run health_drift
    [ -z "$output" ]
}

@test "health_drift: a tool appending to a managed file shows up" {
    # nvm's installer did exactly this to the real repo, and the symptom was
    # `envup upgrade` failing its git pull on an unrelated machine.
    git_repo
    printf 'export NVM_DIR="$HOME/.nvm"\n' >> "$ENVUP_HOME/modules/zsh/files/.zshrc"
    run health_drift
    [[ "$output" == *"modules/zsh/files/.zshrc"* ]]
}
