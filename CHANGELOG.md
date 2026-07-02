# Changelog

All notable changes to envup are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-07-02

First public release.

### Core

- Modular dotfiles / dev-environment manager: a thin CLI (`envup`) + a shared
  library (`lib.sh`) + pluggable modules (`zsh`, `git`, `tmux`, `fzf`, `zoxide`,
  `atuin`, `nvim`).
- Profiles `minimal` / `standard` / `full`, composed via `use_profile`.
- Safe symlinking with automatic backup, idempotent and reversible installs,
  dry-run everywhere, cross-platform package install (apt/dnf/yum/pacman/brew/apk).

### Tooling & quality

- Test suite: bats unit + integration (`scripts/test.sh`); `shellcheck` +
  `bash -n` (`scripts/lint.sh`); GitHub Actions CI matrix (lint / unit /
  integration / smoke on Ubuntu, macOS, and Fedora/Arch/Alpine containers).
- Versioning & releases: `VERSION`, `envup --version`, this changelog, and
  `envup upgrade --ref <tag|branch>` to pin/roll versions.

### Controllability

- `envup status --json` for machine-readable state.
- `ENVUP_LOG_LEVEL` (`debug`/`info`/`warn`/`error`, default `info`) controls
  terminal verbosity; the log file always records everything.

### Extensibility

- `envup doctor`: static validation of module conventions (meta fields,
  function-wrapped hooks, valid `DEPENDS`, and `CLEAN_PATHS` that never target
  user data).
- `ENVUP_GH_MIRROR`: route envup's GitHub downloads through a proxy prefix for
  restricted networks.

### Robustness

- No single step can wedge the whole run: network calls and `pkg_install` are
  wrapped in timeouts, and every module hook runs under an outer watchdog
  (`ENVUP_MODULE_TIMEOUT`, default 900s) — a stuck module is killed and reported
  failed while the install continues with the rest.
- Manifest carries a `# envup-manifest schema=1` header (old headerless
  manifests still read).

### Docs & community

- English + `README.zh-CN.md`, `ARCHITECTURE.md`, `CONTRIBUTING.md`, `TMUX.md`,
  issue/PR templates, `CODE_OF_CONDUCT.md`, `SECURITY.md`.
