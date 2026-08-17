#!/usr/bin/env bats
# The committed per-machine layer.
#
# zsh has had one since 0.2.0 (~/.zshrc.d/hosts/<host>.zsh). tmux, nvim and git
# did not, so anything machine-specific about them — the status bar colour that
# says "this is prod", a toolchain path, a work-only git remote rewrite — had
# nowhere to live except a file outside the checkout that never syncs anywhere.
#
# tmux's source-file and git's [include] both take a fixed path and neither can
# expand a hostname, so envup resolves $ENVUP_HOST at install time and links this
# machine's file to one agreed-upon place. These tests hold that wiring still.

load '../test_helper'

setup() { common_setup; }
teardown() { common_teardown; }

# The shipped meta.sh files, read with the same ENVUP_HOST the engine would use.
meta_links() {
    local mod="$1" host="$2"
    ENVUP_HOST="$host" bash -c "
        HOME='$HOME'; source '$REPO_ROOT/modules/$mod/meta.sh'
        printf '%s\n' \"\${LINKS[@]}\"
    "
}

@test "tmux declares this machine's host file as an optional link" {
    run meta_links tmux thisbox
    [[ "$output" == *"?modules/tmux/files/hosts/thisbox.conf:$HOME/.tmux/host.conf"* ]]
}

@test "git declares this machine's host file as an optional link" {
    run meta_links git thisbox
    [[ "$output" == *"?modules/git/files/hosts/thisbox.gitconfig:$HOME/.gitconfig.host"* ]]
}

@test "the host link is optional, not required" {
    # Without the '?' every machine that has no host file — which is most of
    # them, most of the time — would take a hard link failure on every install.
    run meta_links tmux nosuchbox
    [[ "$output" == *"?modules/tmux/files/hosts/"* ]]
    run meta_links git nosuchbox
    [[ "$output" == *"?modules/git/files/hosts/"* ]]
}

@test "a missing host source is skipped without failing the link pass" {
    mkdir -p "$ENVUP_HOME/modules/m"
    run safe_link_optional "modules/m/hosts/absent.conf" "$HOME/.thing"
    [ "$status" -eq 0 ]
    [ ! -e "$HOME/.thing" ]
}

@test "a missing optional source is reported as fact, not as a warning" {
    # It fires on every machine except the one the file describes. A warning
    # that is correct to ignore is a warning people learn to ignore.
    mkdir -p "$ENVUP_HOME/modules/m"
    run safe_link_optional "modules/m/hosts/absent.conf" "$HOME/.thing"
    [[ "$output" != *"⚠"* ]]
}

@test "doctor --authoring does not warn about an optional source that is absent" {
    # authoring stripped the '?' and then checked the file exists, so declaring
    # a hosts/<host> link made every other machine's authoring run noisy.
    mkdir -p "$ENVUP_HOME/modules/opt"
    cat > "$ENVUP_HOME/modules/opt/meta.sh" <<EOF
#!/bin/bash
NAME="opt"
DESCRIPTION="fixture"
LINKS=("?modules/opt/files/hosts/nowhere.conf:\$HOME/.nowhere")
EOF
    run authoring_module opt
    [[ "$output" != *"does not exist"* ]]
}

@test "doctor --authoring still warns about a required source that is absent" {
    mkdir -p "$ENVUP_HOME/modules/req"
    cat > "$ENVUP_HOME/modules/req/meta.sh" <<EOF
#!/bin/bash
NAME="req"
DESCRIPTION="fixture"
LINKS=("modules/req/files/gone.conf:\$HOME/.gone")
EOF
    run authoring_module req
    [[ "$output" == *"does not exist"* ]]
}

# ---- the config files actually read the layer ----------------------------

@test "tmux.conf sources the host layer, and before the private one" {
    local conf="$REPO_ROOT/modules/tmux/files/.tmux.conf"
    grep -q 'if-shell .*~/.tmux/host.conf.*source-file ~/.tmux/host.conf' "$conf"
    local host_at local_at
    host_at="$(grep -n '~/.tmux/host.conf' "$conf" | tail -1 | cut -d: -f1)"
    local_at="$(grep -n '~/.tmux.local' "$conf" | tail -1 | cut -d: -f1)"
    # Private settings are the ones that must win, so they load last.
    (( host_at < local_at ))
}

@test "tmux sources the host layer after TPM, so it can override a plugin" {
    local conf="$REPO_ROOT/modules/tmux/files/.tmux.conf"
    local tpm_at host_at
    tpm_at="$(grep -n "run '~/.tmux/plugins/tpm/tpm'" "$conf" | cut -d: -f1)"
    host_at="$(grep -n 'source-file ~/.tmux/host.conf' "$conf" | cut -d: -f1)"
    (( tpm_at < host_at ))
}

@test "gitconfig includes generated, then host, then local" {
    local cfg="$REPO_ROOT/modules/git/files/.gitconfig"
    local gen_at host_at local_at
    gen_at="$(grep -n 'path = ~/.gitconfig.envup' "$cfg" | cut -d: -f1)"
    host_at="$(grep -n 'path = ~/.gitconfig.host'  "$cfg" | cut -d: -f1)"
    local_at="$(grep -n 'path = ~/.gitconfig.local' "$cfg" | cut -d: -f1)"
    [[ -n "$gen_at" && -n "$host_at" && -n "$local_at" ]]
    # git applies includes in order and the last writer wins: envup's detection
    # is the weakest claim, your private file the strongest.
    (( gen_at < host_at )) && (( host_at < local_at ))
}

@test "git really does apply the three layers in that order" {
    # Guards the assumption the whole design rests on, against a git that
    # changes its mind about multivalued include.path.
    local h="$TEST_TMP/githome"; mkdir -p "$h"
    printf '[include]\n\tpath = %s/gen\n\tpath = %s/absent\n\tpath = %s/loc\n' \
        "$h" "$h" "$h" > "$h/.gitconfig"
    printf '[x]\n\tk = generated\n\tonlygen = yes\n' > "$h/gen"
    printf '[x]\n\tk = local\n' > "$h/loc"

    run env HOME="$h" XDG_CONFIG_HOME="$h/xdg" git config --list
    [ "$status" -eq 0 ]
    [[ "$output" == *"x.k=local"* ]]        # last layer wins
    [[ "$output" == *"x.onlygen=yes"* ]]    # earlier layers still contribute
}

@test "nvim loads its host file, and before local.lua" {
    local init="$REPO_ROOT/modules/nvim/files/init.lua"
    grep -q 'os_gethostname' "$init"
    local host_at local_at
    host_at="$(grep -n '"/hosts/"' "$init" | cut -d: -f1)"
    local_at="$(grep -n '"/local.lua"' "$init" | cut -d: -f1)"
    [[ -n "$host_at" && -n "$local_at" ]]
    (( host_at < local_at ))
}

@test "nvim strips the domain, so the name matches hostname -s" {
    # ENVUP_HOST is the short name; a box whose gethostname() answers
    # host.corp.example.com must still find hosts/host.lua.
    grep -qF 'gsub("%..*$", "")' "$REPO_ROOT/modules/nvim/files/init.lua"
}

@test "every module with a hosts dir ships a template to copy" {
    [ -f "$REPO_ROOT/modules/tmux/files/hosts/example.conf.template" ]
    [ -f "$REPO_ROOT/modules/git/files/hosts/example.gitconfig.template" ]
    [ -f "$REPO_ROOT/modules/nvim/files/hosts/example.lua.template" ]
    [ -f "$REPO_ROOT/modules/zsh/files/.zshrc.d/hosts/example.zsh.template" ]
}

@test "a template is never mistaken for a real host file" {
    # nvim globs nothing — it builds the path from the hostname — but tmux and
    # git link by name, and a machine called 'example' would otherwise pick up
    # the template. The .template suffix is what prevents that.
    run meta_links tmux example
    [[ "$output" == *"hosts/example.conf:"* ]]
    [[ "$output" != *"example.conf.template"* ]]
}
