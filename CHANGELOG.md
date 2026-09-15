# Changelog

All notable changes to envup are documented here. The project follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-09-16

### Added

- A modular installation engine with explicit providers, dependency ordering,
  dry-run support, timeouts, checksums, pinned release versions, and structured
  state under `~/.local/state/envup`.
- Modules for bat, delta, direnv, eza, fd, jq, lazygit, ripgrep, tealdeer, and
  yazi, plus expanded zsh, tmux, Git, fzf, Atuin, zoxide, and Neovim support.
- Per-machine configuration layers for zsh, tmux, Git, and Neovim, while keeping
  private overrides outside the repository.
- `envup status --json`, `doctor --fix`, `doctor --authoring`, `adopt`, guarded
  `upgrade`, and `clangd sync/status/clean` commands.
- Docker-to-host compilation database translation for clangd, including bind
  mount discovery and automatic Neovim integration.
- Tmux session restore, project switching, Vim-style copy mode, OSC 52 remote
  clipboard support, and seamless `Ctrl-h/j/k/l` navigation across tmux panes
  and Neovim splits.
- Neovim language servers, formatters, diagnostics, Git/TODO tools, persistent
  undo and sessions, large-file safeguards, and a compatible build for older
  glibc systems.
- CI and integration coverage for Linux distributions, macOS, old Bash, module
  contracts, installation safety, shell startup, tmux, and Neovim configuration.

### Changed

- Installation is idempotent and preserves existing user files by backing them
  up before creating managed links.
- Shared HOME directories use host-scoped state and tmux restore data.
- Shell startup is split into ordered, focused configuration slices and avoids
  duplicate PATH entries, unconditional locale/timezone overrides, and eager
  loading of heavy tools.
- Public documentation is consolidated into the English/Chinese READMEs and a
  compact contributor guide; machine-specific files and internal reports are
  excluded from the release.

### Fixed

- Neovim installation on hosts whose glibc is too old for current upstream
  binaries.
- Tmux copy-mode status rendering, clipboard behaviour, session restore paths,
  and window movement focus.
- Upgrade diagnostics for dirty worktrees, detached HEADs, missing upstreams,
  and edits made through managed symlinks.
- Cross-platform package names, release asset selection, shell compatibility,
  and partial-download handling.

[Unreleased]: https://github.com/gendu-amd/envup/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/gendu-amd/envup/releases/tag/v0.1.0
