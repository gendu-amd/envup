#!/bin/bash
# Yazi's companion `ya` command manages packages and talks to running instances.

verify() {
    bin_path yazi >/dev/null && bin_runs yazi &&
        bin_path ya >/dev/null && bin_runs ya
}
