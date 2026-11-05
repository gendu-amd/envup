#!/usr/bin/env bats
# ENVUP_LOG_LEVEL gates terminal output; error is always shown, debug is hidden
# by default. (The log file, via _logf, is unaffected — not covered here.)

load '../test_helper'

setup() { common_setup; }
teardown() { common_teardown; }

@test "log_info: shown at default (info), hidden at warn" {
    run log_info "HELLO"
    [ "$status" -eq 0 ]; [[ "$output" == *HELLO* ]]
    ENVUP_LOG_LEVEL=warn run log_info "HELLO"
    [ "$status" -eq 0 ]; [ -z "$output" ]
}

@test "log_warn: shown at warn, hidden at error" {
    ENVUP_LOG_LEVEL=warn  run log_warn "WARNME"; [[ "$output" == *WARNME* ]]
    ENVUP_LOG_LEVEL=error run log_warn "WARNME"; [ -z "$output" ]
}

@test "log_error: always shown (info, warn, error)" {
    run log_error "BOOM";                        [[ "$output" == *BOOM* ]]
    ENVUP_LOG_LEVEL=warn  run log_error "BOOM";  [[ "$output" == *BOOM* ]]
    ENVUP_LOG_LEVEL=error run log_error "BOOM";  [[ "$output" == *BOOM* ]]
}

@test "log_debug: hidden by default, shown at debug" {
    run log_debug "DBG";                         [ -z "$output" ]
    ENVUP_LOG_LEVEL=debug run log_debug "DBG";   [[ "$output" == *DBG* ]]
}
