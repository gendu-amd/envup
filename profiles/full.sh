# shellcheck shell=bash
# shellcheck disable=SC2034  # MODULES is consumed by load_profile() via sourcing
# Profile: full — power-user workstation. = standard + editor.
use_profile standard
MODULES+=(nvim)
