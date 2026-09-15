#!/bin/bash
# Module: jq — portable JSON processing for shell pipelines and envup output.
# shellcheck disable=SC2034  # metadata is consumed by lib/engine.sh

NAME="jq"
DESCRIPTION="JSON processor for APIs, logs and command pipelines"
DEPENDS=()

VERIFY_BIN="jq"
PROVIDERS=(system github_release)
GH_REPO="jqlang/jq"

LINKS=()
CLEAN_PATHS=()
