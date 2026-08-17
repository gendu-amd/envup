#!/usr/bin/env bats
# The dispatcher's argument handling.
#
# Two things are being pinned here, and both are about what happens when the
# command line is *wrong*:
#
#   1. No option can hang. envup's headline promise is that no step can hang the
#      whole run, and every network call is time-boxed to keep it — which was
#      worth very little while `envup upgrade --profile` with the value left off
#      spun forever in the argument loop, before any of that machinery ran.
#      `shift 2` with one argument remaining fails *without shifting*, so
#      `while (($#))` never advances.
#
#   2. A wrong option is refused, not ignored. Printing the human table for
#      `status --jsonn` is the worst available answer for a script that asked
#      for JSON, and reading it back is how you find out.

load '../test_helper'

setup() {
    common_setup
    # envup derives ENVUP_HOME from its own path, so it has to be run from
    # inside the sandbox for these to stay off the real machine.
    ln -sf "$REPO_ROOT/envup"   "$ENVUP_HOME/envup"
    ln -sf "$REPO_ROOT/VERSION" "$ENVUP_HOME/VERSION"
    mkdir -p "$ENVUP_HOME/profiles"
}
teardown() { common_teardown; }

# Every option that takes a value, invoked with the value missing. The table is
# the point: an option added later gets a line here and is covered for free.
@test "no command hangs when an option's value is missing" {
    local args
    for args in "install --profile" "install -p" \
                "upgrade --profile" "upgrade -p" \
                "upgrade --ref"     "upgrade -r" \
                "doctor --module"; do
        # shellcheck disable=SC2086  # deliberate word splitting of the table row
        run timeout 10 "$ENVUP_HOME/envup" $args
        [ "$status" -ne 124 ] || { echo "hung: envup $args"; return 1; }
        [ "$status" -ne 0 ]   || { echo "silently accepted: envup $args"; return 1; }
    done
}

@test "upgrade --profile with no value names the option it is complaining about" {
    run timeout 10 "$ENVUP_HOME/envup" upgrade --profile
    [ "$status" -eq 1 ]
    [[ "$output" == *"--profile needs a name"* ]]
}

@test "status: a misspelt option is refused, not answered with the wrong format" {
    run "$ENVUP_HOME/envup" status --jsonn
    [ "$status" -ne 0 ]
    [[ "$output" == *"unknown option"* ]]
    [[ "$output" != *"Modules:"* ]]
}

@test "status: --json and no-args both still work" {
    run "$ENVUP_HOME/envup" status --json
    [ "$status" -eq 0 ]
    [[ "$output" == "{"* ]]
    run "$ENVUP_HOME/envup" status
    [ "$status" -eq 0 ]
    [[ "$output" == *"Modules:"* ]]
}

@test "log: --help prints usage instead of dumping a log" {
    run "$ENVUP_HOME/envup" log --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: envup log"* ]]
}

@test "log: a misspelt option is refused" {
    run "$ENVUP_HOME/envup" log --tial
    [ "$status" -ne 0 ]
    [[ "$output" == *"unknown option"* ]]
}

# `--dry-runn` used to be reported as "no module: dry-runn", which sends you
# looking for a module instead of at the flag you mistyped.
@test "clean: a misspelt option is reported as an option, not as a module" {
    run "$ENVUP_HOME/envup" clean --dry-runn
    [ "$status" -ne 0 ]
    [[ "$output" == *"unknown option"* ]]
}

@test "--help and --version do not create a log file" {
    "$ENVUP_HOME/envup" --help  >/dev/null
    "$ENVUP_HOME/envup" --version >/dev/null
    "$ENVUP_HOME/envup" doctor --help >/dev/null
    [ ! -d "$ENVUP_STATE_DIR/logs" ]
}

# doctor and adopt both change the machine — --fix rebuilds links and drops
# manifest orphans, adopt moves content between files and runs git checkout.
# Every other command that does that leaves a record; for a long time these two
# didn't, so the one repair you later needed to explain was the unlogged one.
@test "doctor leaves a log behind" {
    run "$ENVUP_HOME/envup" doctor
    [ -d "$ENVUP_STATE_DIR/logs" ]
    run bash -c 'ls "$ENVUP_STATE_DIR"/logs/doctor_*.log'
    [ "$status" -eq 0 ]
}

@test "adopt leaves a log behind" {
    git -C "$ENVUP_HOME" init -q 2>/dev/null || skip "no git"
    run "$ENVUP_HOME/envup" adopt
    run bash -c 'ls "$ENVUP_STATE_DIR"/logs/adopt_*.log'
    [ "$status" -eq 0 ]
}

# ---- completions track the parsers --------------------------------------
#
# A completion that is missing an option is not a cosmetic gap: `envup upgrade
# --ref v0.1.0` is how you pin or roll back a release, and for as long as the
# completion didn't know the flag, the flag might as well not have existed.
# Checked against the parsers rather than against a list kept here, so an
# option added later is covered without anybody remembering to come back.

# _parser_opts <function-name> <file> — the long options a parser accepts.
_parser_opts() {
    sed -n "/^$1()/,/^}/p" "$2" |
        grep -oE '^[[:space:]]+[^)]*--[a-z][a-z-]*\)' |
        grep -oE '\-\-[a-z][a-z-]*' | sort -u
}

@test "every option a command parses is offered by the zsh completion" {
    local comp="$REPO_ROOT/completions/_envup" spec fn file opt
    for spec in "cmd_install:$REPO_ROOT/envup"    "cmd_uninstall:$REPO_ROOT/envup" \
                "cmd_upgrade:$REPO_ROOT/envup"    "cmd_status:$REPO_ROOT/envup" \
                "cmd_clean:$REPO_ROOT/envup"      "cmd_log:$REPO_ROOT/envup" \
                "doctor_main:$REPO_ROOT/lib/doctor.sh" \
                "adopt_main:$REPO_ROOT/lib/adopt.sh"; do
        fn="${spec%%:*}"; file="${spec#*:}"
        while read -r opt; do
            [[ -n "$opt" ]] || continue
            # '*' prefixes a repeatable option in an _arguments spec.
            grep -qE -- "'\*?$opt\[" "$comp" || {
                echo "$fn accepts $opt but completions/_envup never offers it"
                return 1
            }
        done < <(_parser_opts "$fn" "$file")
    done
}
@test "logs are written under ENVUP_STATE_DIR, not a hardcoded \$HOME path" {
    "$ENVUP_HOME/envup" doctor >/dev/null 2>&1 || true
    [ -d "$ENVUP_STATE_DIR/logs" ]
    [ ! -d "$HOME/.local/state/envup/logs" ]
}
