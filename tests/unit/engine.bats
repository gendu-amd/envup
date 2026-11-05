#!/usr/bin/env bats
# Provider selection, result states, linking, and verification.

load '../test_helper'

setup() { common_setup; }
teardown() { common_teardown; }

# mk_meta <name> <meta.sh body> — a fixture module.
mk_meta() {
    local n="$1"; shift
    mkdir -p "$ENVUP_HOME/modules/$n"
    printf '#!/bin/bash\nNAME="%s"\nDESCRIPTION="fixture"\n%s\n' "$n" "$*" \
        > "$ENVUP_HOME/modules/$n/meta.sh"
}
mk_hooks() { printf '#!/bin/bash\n%s\n' "$2" > "$ENVUP_HOME/modules/$1/hooks.sh"; }

# ---- package naming ------------------------------------------------------

@test "pkg_name: uses the entry for this machine's packaging family" {
    NAME=fd; PKG_DEFAULT=""; PKG_NAMES=(debian:fd-find rhel:fd-find brew:fd)
    ENVUP_PKG=apt run pkg_name
    [ "$output" = "fd-find" ]
}

@test "pkg_name: falls back to PKG_DEFAULT, then to the module name" {
    NAME=nvim; PKG_NAMES=(); PKG_DEFAULT=neovim
    run pkg_name
    [ "$output" = "neovim" ]

    PKG_DEFAULT=""
    run pkg_name
    [ "$output" = "nvim" ]
}

# ---- version comparison --------------------------------------------------

@test "version_ge: 0.10 sorts above 0.9, not below it" {
    # The bug this guards: a lexical compare puts 0.9 after 0.10, so an nvim
    # 0.9.5 that is genuinely too old reads as new enough.
    version_ge 0.11.3 0.10
    version_ge 0.10.0 0.10
    ! version_ge 0.9.5 0.10
}

# The same version written to different depths. sort -V puts the shorter string
# first, so this used to read "0.9 is older than 0.9.0" and send a perfectly
# good tool back through the install chain.
@test "version_ge: trailing zero components do not change the version" {
    version_ge 0.9 0.9.0
    version_ge 0.9.0 0.9
    version_ge 1 1.0.0
    version_ge 1.0.0 1
    ! version_ge 1.2 1.2.1
    version_ge 1.20 1.2
}

@test "version_ge: equal versions satisfy the floor" {
    version_ge 1.2.3 1.2.3
}

policy_fixture() {
    NAME=fixture VERIFY_BIN=fixture VERIFY_MIN_VERSION=0.5 VERIFY_VERSION_ARG=--version
    GH_TAG="" PROVIDERS=(system github_release)
    printf 'fixture v2.0\n' > "$ENVUP_HOME/versions.lock"
    stub_bin fixture <<'EOF'
#!/bin/sh
echo fixture 1.0
EOF
    provider_system() { echo 'unexpected system route'; return 1; }
}

@test "reuse policy keeps a compatible tool even when the release pin is newer" {
    policy_fixture
    ENVUP_TOOL_POLICY=reuse run _engine_tool
    [ "$status" -eq 0 ]
    [[ "$output" != *'unexpected system route'* ]]
    [ "$(bin_version fixture)" = 1.0 ]
}

@test "locked policy uses the release route rather than the package manager" {
    policy_fixture
    provider_github_release() {
        printf '#!/bin/sh\necho fixture 2.0\n' > "$STUB_BIN/fixture"
    }
    ENVUP_TOOL_POLICY=locked run _engine_tool
    [ "$status" -eq 0 ]
    [[ "$output" != *'unexpected system route'* ]]
    [ "$(bin_version fixture)" = 2.0 ]
}

@test "locked policy reuses a matching compatibility override" {
    policy_fixture
    GH_TAG=v1.0.0
    provider_github_release() { echo 'unexpected release route'; return 1; }
    ENVUP_TOOL_POLICY=locked run _engine_tool
    [ "$status" -eq 0 ]
    [[ "$output" != *'unexpected release route'* ]]
}

@test "locked policy fails when offline without discarding the existing tool" {
    policy_fixture
    provider_github_release() { return "$ENVUP_RC_UNAVAIL"; }
    ENVUP_TOOL_POLICY=locked run _engine_tool
    [ "$status" -eq 1 ]
    [ "$(bin_version fixture)" = 1.0 ]
}

@test "locked policy cannot silently install the wrong version or omit a pin" {
    policy_fixture
    provider_github_release() { return 0; }
    ENVUP_TOOL_POLICY=locked run _engine_tool
    [ "$status" -eq 1 ]
    rm "$ENVUP_HOME/versions.lock"
    ENVUP_TOOL_POLICY=locked run _engine_tool
    [ "$status" -eq 1 ]
}

@test "engine records the resolved binary and checkout revision for reused tools" {
    mk_meta fixture 'VERIFY_BIN=fixture'
    stub_bin fixture <<'EOF'
#!/bin/sh
echo fixture 1.0
EOF
    git -C "$ENVUP_HOME" init -q
    git -C "$ENVUP_HOME" add modules/fixture/meta.sh
    git -C "$ENVUP_HOME" -c user.name=fixture -c user.email=fixture@example.invalid commit -qm fixture
    local revision; revision="$(git -C "$ENVUP_HOME" rev-parse HEAD)"
    engine_install fixture
    [ "$(manifest_get fixture path)" = "$STUB_BIN/fixture" ]
    [ "$(manifest_get fixture source_revision)" = "$revision" ]
    [ "$(manifest_get fixture provider)" = preinstalled ]
    [ -z "$(manifest_get fixture release_tag)" ]
}

# ---- "installed" is not the same as "runs here" --------------------------
# A binary can be on PATH, be +x, and still be unusable: the everyday cause is a
# prebuilt release built against a newer glibc than the server has. It exits
# non-zero with `version \`GLIBC_2.33' not found` — a message that happens to
# contain a dotted number, which is how envup once reported nvim as "ok (2.33)".

# A stub that behaves exactly like that failure.
stub_wontrun() {
    stub_bin "$1" <<EOF
#!/bin/bash
echo "$1: /lib64/libc.so.6: version \\\`GLIBC_2.33' not found" >&2
exit 1
EOF
}

@test "bin_version: a non-zero exit yields no version, not one scraped from the error" {
    stub_wontrun brokenbin
    VERIFY_VERSION_ARG="--version"
    run bin_version brokenbin
    [ "$status" -ne 0 ]
    [ -z "$output" ]
}

@test "bin_version: reads a banner printed on stderr, but only after a clean exit" {
    stub_bin talksonstderr <<'EOF'
#!/bin/bash
echo "talksonstderr 4.5.6" >&2
exit 0
EOF
    VERIFY_VERSION_ARG="--version"
    run bin_version talksonstderr
    [ "$status" -eq 0 ]
    [ "$output" = "4.5.6" ]
}

@test "bin_version: prefers stdout when the tool writes to both" {
    stub_bin bothstreams <<'EOF'
#!/bin/bash
echo "warning: config 9.9.9 is deprecated" >&2
echo "bothstreams 1.2.3"
EOF
    VERIFY_VERSION_ARG="--version"
    run bin_version bothstreams
    [ "$output" = "1.2.3" ]
}

@test "bin_runs: separates 'not on PATH' from 'there but will not execute'" {
    stub_wontrun deadbin
    VERIFY_VERSION_ARG="--version"
    ! bin_runs deadbin              # present, does not run
    bin_path deadbin >/dev/null     # …and bin_path still finds it
    ! bin_runs no-such-binary-anywhere
}

@test "engine_verify: an unrunnable binary is not installed, even with no version floor" {
    # No VERIFY_MIN_VERSION is the common case (6 of 7 shipped modules). The old
    # engine_verify returned early on bin_path alone, so those modules could
    # never notice a broken binary at all.
    stub_wontrun ghost
    VERIFY_BIN=ghost; VERIFY_MIN_VERSION=""; VERIFY_VERSION_ARG="--version"
    ! engine_verify
}

@test "engine_verify: VERIFY_VERSION_ARG covers a tool with no --version (tmux < 3.1)" {
    # tmux before 3.1 answers -V and prints usage to stderr with exit 1 for
    # anything else. Judging it by --version would call a working tmux broken.
    stub_bin oldtmux <<'EOF'
#!/bin/bash
[[ "$1" == "-V" ]] && { echo "tmux 2.7"; exit 0; }
echo "usage: tmux [-2CluvV]" >&2
exit 1
EOF
    VERIFY_BIN=oldtmux; VERIFY_MIN_VERSION=""
    VERIFY_VERSION_ARG="--version"; ! engine_verify
    VERIFY_VERSION_ARG="-V";          engine_verify
    run bin_version oldtmux
    [ "$output" = "2.7" ]
}

@test "the shipped tmux module asks tmux on the flag tmux answers" {
    # Guards the meta.sh field rather than the engine: without it, every tmux
    # older than 3.1 reports 'broken' on an otherwise healthy machine.
    run bash -c "source '$REPO_ROOT/modules/tmux/meta.sh' >/dev/null 2>&1; echo \$VERIFY_VERSION_ARG"
    [ "$output" = "-V" ]
}

# ---- the four states -----------------------------------------------------

@test "engine_install: a config-only module links its files and reports ok" {
    mkdir -p "$ENVUP_HOME/files"
    echo hello > "$ENVUP_HOME/files/thing"
    mk_meta cfg 'LINKS=("files/thing:$HOME/.thing")'

    run engine_install cfg
    [ "$status" -eq 0 ]
    [ -L "$HOME/.thing" ]
    [ "$(cat "$HOME/.thing")" = hello ]
}

@test "engine_install: APPLIES_IF that is false yields 'skipped', not a failure" {
    mk_meta nope 'APPLIES_IF="false"'
    run engine_install nope
    [ "$status" -eq "$ENVUP_RC_SKIPPED" ]
    [ "$(engine_state_label "$status")" = skipped ]
}

@test "engine_install: no route to the tool is 'degraded' — and the config still lands" {
    # This is the whole point of the state. On a server with no root and no
    # package, zsh cannot be installed; linking the config anyway means the
    # machine is correct the moment an admin installs it.
    mkdir -p "$ENVUP_HOME/files"
    echo rc > "$ENVUP_HOME/files/rc"
    mk_meta locked 'VERIFY_BIN="definitely-not-a-real-binary"
PROVIDERS=(manual)
LINKS=("files/rc:$HOME/.rc")'

    run engine_install locked
    [ "$status" -eq "$ENVUP_RC_DEGRADED" ]
    [ "$(engine_state_label "$status")" = degraded ]
    [[ "$output" == *"by hand"* ]]

    # ...and the link exists despite the tool being absent. (`run` above swallows
    # side effects into a subshell, so do it again for real — still degraded.)
    engine_install locked >/dev/null 2>&1 || true
    [ -L "$HOME/.rc" ]
}

@test "engine_install: a failing pre_install fails the module" {
    mk_meta broken ''
    mk_hooks broken 'pre_install() { return 1; }'
    run engine_install broken
    [ "$status" -eq 1 ]
    [ "$(engine_state_label "$status")" = failed ]
}

@test "engine_install: hooks run in order around the links" {
    mkdir -p "$ENVUP_HOME/files"; : > "$ENVUP_HOME/files/f"
    mk_meta seq 'LINKS=("files/f:$HOME/.f")'
    mk_hooks seq 'pre_install()  { [[ -e "$HOME/.f" ]] && echo "TOO-EARLY"; echo pre; }
post_install() { [[ -L "$HOME/.f" ]] || echo "NOT-LINKED"; echo post; }'

    run engine_install seq
    [ "$status" -eq 0 ]
    [[ "$output" != *TOO-EARLY* ]]
    [[ "$output" != *NOT-LINKED* ]]
    [[ "$output" == *pre* && "$output" == *post* ]]
}

@test "engine_install: a post_install that returns 'degraded' degrades, it does not fail" {
    # nvim on a machine with no git: the editor and its config are installed and
    # working, only the plugin set is short. Calling that a failure made a whole
    # profile exit 1 over something the user may not even care about.
    mk_meta half 'VERIFY_BIN="sh"'
    mk_hooks half 'post_install() {
    _ENG_HOOK_REASON="the optional half is missing"
    return "$ENVUP_RC_DEGRADED"
}'
    run engine_install half
    [ "$status" -eq "$ENVUP_RC_DEGRADED" ]
    [ "$(engine_state_label "$status")" = degraded ]
    [[ "$output" == *"the optional half is missing"* ]]
}

@test "engine_install: a post_install that really fails still fails" {
    mk_meta reallybad ''
    mk_hooks reallybad 'post_install() { return 1; }'
    run engine_install reallybad
    [ "$status" -eq 1 ]
    [[ "$output" == *"post_install failed"* ]]
}

# ---- dry-run (A9) --------------------------------------------------------

@test "engine_install: --dry-run neither installs nor judges the machine for it (A9)" {
    # The old nvim hook skipped the install under dry-run and then version-checked
    # the nvim that was never installed, so every machine without nvim failed a
    # *preview* with the misleading "nvim too old: " (empty version).
    ENVUP_DRY_RUN=1
    mk_meta prev 'VERIFY_BIN="definitely-not-a-real-binary"
VERIFY_MIN_VERSION="9.9"
PROVIDERS=(system github_release)'

    run engine_install prev
    [ "$status" -eq 0 ]
    [[ "$output" == *"[dry-run]"* ]]
    [[ "$output" != *"too old"* ]]
}

@test "engine_install: --dry-run creates no symlinks" {
    ENVUP_DRY_RUN=1
    mkdir -p "$ENVUP_HOME/files"; : > "$ENVUP_HOME/files/f"
    mk_meta prev2 'LINKS=("files/f:$HOME/.f")'
    run engine_install prev2
    [ "$status" -eq 0 ]
    [ ! -e "$HOME/.f" ]
}

# ---- the provider chain --------------------------------------------------

@test "_engine_tool: an unavailable provider is skipped quietly and the chain continues" {
    NAME=chain; VERIFY_BIN=chained; VERIFY_MIN_VERSION=""; VERIFY_VERSION_ARG=--version
    PROVIDERS=(system manual)
    # system declines: no package name for this family, and no privileges.
    PKG_NAMES=(); PKG_DEFAULT="-"

    run _engine_tool
    [ "$status" -eq "$ENVUP_RC_DEGRADED" ]
    # "does not apply" is a debug line, never a warning: an absent route is not
    # a fault, and a wall of scary warnings is how people stop reading output.
    [[ "$output" != *"provider system failed"* ]]
    [[ "$output" == *"by hand"* ]]
}

@test "_engine_tool: a provider that succeeds ends the chain" {
    # /bin/sh is dash on Debian/Ubuntu and deliberately rejects --version.
    # Use the Bash floor envup itself requires so this fixture means the same
    # thing on every supported distribution.
    NAME=found; VERIFY_BIN=bash; VERIFY_MIN_VERSION=""; VERIFY_VERSION_ARG=--version
    PROVIDERS=(manual)
    run _engine_tool
    [ "$status" -eq 0 ]
    # sh already exists, so the chain is never entered at all.
    [[ "$output" != *"by hand"* ]]
}

@test "_engine_tool: an unknown provider name is a real failure, not a shrug" {
    NAME=typo; VERIFY_BIN=definitely-not-a-real-binary
    VERIFY_MIN_VERSION=""; VERIFY_VERSION_ARG=--version
    PROVIDERS=(githubrelease)
    run _engine_tool
    [ "$status" -eq 1 ]
    [[ "$output" == *"unknown provider"* ]]
}

@test "_engine_tool: manual and unavailable routes do not erase an earlier failure" {
    NAME=chain; VERIFY_BIN=definitely-not-a-real-binary
    VERIFY_MIN_VERSION=""; VERIFY_VERSION_ARG=--version
    provider_system() { return 1; }
    provider_github_release() { return "$ENVUP_RC_UNAVAIL"; }
    local chain
    for chain in 'system' 'system manual' 'system github_release manual'; do
        # shellcheck disable=SC2206
        PROVIDERS=($chain)
        run _engine_tool
        [ "$status" -eq 1 ]
    done
}

@test "_engine_tool: a later verified install recovers from failure or manual guidance" {
    NAME=chain; VERIFY_BIN=recovered
    VERIFY_MIN_VERSION=""; VERIFY_VERSION_ARG=--version
    provider_system() { return 1; }
    provider_script() {
        stub_bin recovered <<'SH'
#!/bin/bash
echo 'recovered 1.0'
SH
    }
    local chain
    for chain in 'system script' 'manual script' 'system manual script'; do
        rm -f "$STUB_BIN/recovered"
        # shellcheck disable=SC2206
        PROVIDERS=($chain)
        run _engine_tool
        [ "$status" -eq 0 ]
        [[ "$output" == *"provider system failed"* || "$chain" == 'manual script' ]]
        bin_runs recovered
    done
}

@test "_engine_tool: provider success without a usable tool is still a failure" {
    NAME=chain; VERIFY_BIN=definitely-not-a-real-binary
    VERIFY_MIN_VERSION=""; VERIFY_VERSION_ARG=--version
    PROVIDERS=(system manual)
    provider_system() { return 0; }
    run _engine_tool
    [ "$status" -eq 1 ]
    [[ "$output" == *"still does not check out"* ]]
}

@test "engine_install: a tool installation error stops before links and post_install" {
    mkdir -p "$ENVUP_HOME/files"
    echo shared > "$ENVUP_HOME/files/config"
    mk_meta broken 'VERIFY_BIN="definitely-not-a-real-binary"
PROVIDERS=(git manual)
LINKS=("files/config:$HOME/.config-fixture")'
    mk_hooks broken 'post_install() { touch "$HOME/post-ran"; }'
    run engine_install broken
    [ "$status" -eq 1 ]
    [[ "$output" == *"git provider needs GIT_URL"* ]]
    [[ "$output" == *"git (rc=1)"* ]]
    [ ! -e "$HOME/.config-fixture" ]
    [ ! -e "$HOME/post-ran" ]
    ! manifest_has broken
}

# ---- links ---------------------------------------------------------------

@test "_engine_links: a malformed entry is reported instead of silently ignored" {
    NAME=bad; LINKS=("files/x")
    run _engine_links
    [ "$status" -ne 0 ]
    [[ "$output" == *"malformed"* ]]
}

@test "_engine_links: a '?' entry tolerates a missing source" {
    NAME=opt; LINKS=("?files/never-existed:$HOME/.never")
    run _engine_links
    [ "$status" -eq 0 ]
}

@test "engine_uninstall: removes the links and leaves the binary alone" {
    mkdir -p "$ENVUP_HOME/files"; : > "$ENVUP_HOME/files/f"
    mk_meta rm1 'VERIFY_BIN="bash"
LINKS=("files/f:$HOME/.f")'
    engine_install rm1 >/dev/null 2>&1
    [ -L "$HOME/.f" ]

    run engine_uninstall rm1
    [ "$status" -eq 0 ]
    [ ! -e "$HOME/.f" ]
    command -v bash >/dev/null     # never touched
}

# ---- result labels -------------------------------------------------------

@test "engine_state_label: a watchdog kill reads as timeout, not as a mystery" {
    [ "$(engine_state_label 0)" = ok ]
    [ "$(engine_state_label "$ENVUP_RC_DEGRADED")" = degraded ]
    [ "$(engine_state_label "$ENVUP_RC_SKIPPED")" = skipped ]
    [ "$(engine_state_label 124)" = timeout ]
    [ "$(engine_state_label 1)" = failed ]
}

@test "engine result codes do not collide with the ones timeout uses" {
    # 124/137/143 come from `timeout` itself; a state code reusing one of them
    # would turn a killed module into a "degraded" success.
    for rc in "$ENVUP_RC_DEGRADED" "$ENVUP_RC_SKIPPED" "$ENVUP_RC_UNAVAIL" \
              "$ENVUP_RC_NOPRIV" "$ENVUP_RC_OFFLINE"; do
        [ "$rc" -ne 124 ] && [ "$rc" -ne 137 ] && [ "$rc" -ne 143 ] && [ "$rc" -ne 0 ]
    done
}

@test "engine_install: a failed post hook leaves partial configuration and records its phase" {
    mkdir -p "$ENVUP_HOME/files"; echo shared > "$ENVUP_HOME/files/config"
    mk_meta partial 'LINKS=("files/config:$HOME/.config-fixture")'
    mk_hooks partial 'post_install() { touch "$HOME/partial-work"; return 1; }'
    run engine_install partial
    [ "$status" -eq 1 ]
    [ -L "$HOME/.config-fixture" ]
    [ -e "$HOME/partial-work" ]
    ! manifest_has partial
    [ "$(manifest_install_get partial state)" = failed ]
    [ "$(manifest_install_get partial phase)" = post_install ]
    mk_hooks partial 'post_install() { return 0; }'
    run engine_install partial
    [ "$status" -eq 0 ]
    manifest_has partial
    [ "$(manifest_install_get partial state)" = ok ]
}

@test "engine_install: failed retries preserve the prior successful install record" {
    mk_meta retry ''
    manifest_record retry ok system 1.0
    mk_hooks retry 'pre_install() { return 1; }'
    run engine_install retry
    [ "$status" -eq 1 ]
    [ "$(manifest_get retry state)" = ok ]
    [ "$(manifest_get retry provider)" = system ]
    [ "$(manifest_get retry version)" = 1.0 ]
    [ "$(manifest_install_get retry phase)" = pre_install ]
}

@test "engine_install: progress write failure stops before any hook" {
    mk_meta blocked ''
    mk_hooks blocked 'pre_install() { touch "$HOME/hook-ran"; }'
    manifest_install_record() { return 1; }
    run engine_install blocked
    [ "$status" -eq 1 ]
    [ ! -e "$HOME/hook-ran" ]
    [[ "$output" == *"could not record installation progress"* ]]
}

@test "engine_install: installed-row write failure is not reported as success" {
    mk_meta blocked ''
    manifest_record() { return 1; }
    run engine_install blocked
    [ "$status" -eq 1 ]
    [ "$(manifest_install_get blocked state)" = failed ]
    [ "$(manifest_install_get blocked phase)" = record ]
    ! manifest_has blocked
}

@test "engine_install: post-install component gaps are checked and recorded as degraded" {
    mk_meta half ''
    mk_hooks half 'check_health() { echo "optional component missing"; return 70; }'
    run engine_install half
    [ "$status" -eq 70 ]
    [ "$(manifest_get half state)" = degraded ]
    [ "$(manifest_install_get half reason)" = "optional component missing" ]
}

@test "engine_install: a hook removing a managed link fails final acceptance" {
    mkdir -p "$ENVUP_HOME/files"; touch "$ENVUP_HOME/files/f"
    mk_meta damaged 'LINKS=("files/f:$HOME/.f")'
    mk_hooks damaged 'post_install() { rm "$HOME/.f"; }'
    run engine_install damaged
    [ "$status" -eq 1 ]
    ! manifest_has damaged
    [ "$(manifest_install_get damaged phase)" = check_health ]
}

@test "engine_install: preview does not run component acceptance on uninstalled files" {
    mk_meta preview ''
    mk_hooks preview 'check_health() { touch "$HOME/check-ran"; return 1; }'
    ENVUP_DRY_RUN=1 run engine_install preview
    [ "$status" -eq 0 ]
    [ ! -e "$HOME/check-ran" ]
}

@test "engine_install: a post hook breaking a verified tool fails final acceptance" {
    stub_bin working <<'EOF'
#!/bin/bash
echo fixture-1.0
EOF
    mk_meta damaged 'VERIFY_BIN=working'
    mk_hooks damaged 'post_install() { printf "#!/bin/bash\nexit 1\n" > "$STUB_BIN/working"; }'
    run engine_install damaged
    [ "$status" -eq 1 ]
    ! manifest_has damaged
    [ "$(manifest_install_get damaged phase)" = check_health ]
}

@test "engine_install: a broken component check fails instead of becoming optional" {
    mk_meta broken ''
    mk_hooks broken 'check_health() { echo "component check broken"; return 1; }'
    run engine_install broken
    [ "$status" -eq 1 ]
    ! manifest_has broken
    [ "$(manifest_install_get broken phase)" = check_health ]
    [[ "$(manifest_install_get broken reason)" == *"component check broken"* ]]
}
