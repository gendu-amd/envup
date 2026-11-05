# Changelog

All notable changes to envup are documented here. The project follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

The initial baseline contains the following capabilities and fixes.

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

- Shared-HOME user-space binaries and application trees default to directories
  keyed by short hostname. Explicit install directories retain precedence.

- `upgrade --tools reuse|locked` separates compatible-tool reuse from GitHub
  release version matching. Install records include command paths, source
  revisions, and release tags, exposed as `installed_tool` in status JSON.
- Neovim's private `envup.json` accepts a `languages` array shared by tool
  installation/checks, LSP, formatters and Treesitter parser selection. Omitted
  selection preserves the full set; an empty array selects none. Opening files
  no longer automatically installs parsers outside this selection.
- Private Neovim `envup.json` supports `{"plugins": false}` for core editing.
  Startup, installation and health checks share this selection; core mode
  skips plugin and language-tool setup and does not require Git. Legacy config
  migration preserves the selection alongside `local.lua`.

### Changed

- Deployment guidance separates module health from functional acceptance and
  documents session ownership and host/container compilation database paths.
- Nvim uninstall guidance distinguishes disposable caches from retained plugins,
  language tools and editor state. Library introductions describe current
  contracts without repeating historical implementation narratives.

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

- Link repair refuses destination parents that resolve into the checkout, so
  legacy directory links cannot move source files into backup or create loops.
- Neovim's tmux sessions carry a content checksum. Existing user sessions,
  edited generated sessions, and replacement symlinks are preserved; clean exits
  remove only unchanged sessions owned by the current process.

- Neovim installation on hosts whose glibc is too old for current upstream
  binaries.
- Tmux copy-mode status rendering, clipboard behaviour, session restore paths,
  and window movement focus.
- Upgrade diagnostics for dirty worktrees, detached HEADs, missing upstreams,
  and edits made through managed symlinks.
- Cross-platform package names, release asset selection, shell compatibility,
  and partial-download handling.

- Neovim cold installation supplies Lazy's branch when its shallow stable-tag
  bootstrap has detached HEAD. Lazy writes a user-state lock instead of truncating
  the checkout's pinned lock when plugin operations fail.

- Copy-only OSC 52 and WSL clipboard providers preserve local register selection
  types when pasting, including blockwise text, without querying the terminal.

- Commands with no optional arguments work under Bash 4.0 with `set -u`,
  including status, authoring checks, doctor and clangd dispatch. Legacy Bash
  CI checks command exit codes and the offline Git configuration lifecycle.

- Zsh and tmux entry points follow the selected user-space tool directory.
  Platform CI exercises real releases, including old glibc and musl.
- Manifest lock waiters no longer reclaim directories from a stale PID
  observation, which could remove a new writer's lock and lose concurrent rows.
  Leftover locks require inspection and manual cleanup after a bounded wait.
- Clangd keeps the nearest project root on Nvim 0.12 as well as 0.10, including
  files that have not yet been saved.

- Source upgrades require a fast-forward, report changed revisions after partial
  failures, and run installation with the selected checkout's CLI and libraries.
- GitHub releases are checked before replacement and at their installed paths.
  Failed activation restores previous binaries, symlinks, and runtime trees;
  failed restoration retains backups and reports their location.
- Offline Neovim startup disables automatic plugin/resource installation and
  falls back to core editing for incomplete plugin/theme caches. Offline install
  checks cached components without restore/sync or deleting partial caches.
  Lazy bootstrap is performed by envup installation rather than startup.
- zoxide, atuin, direnv, and delta can be installed without adopting envup's
  shell/Git configuration. Delta only refreshes a managed Git configuration.
  Generated Git config refuses symlink destinations and propagates write errors.
- Installation now accepts final links and module components using the same
  bounded health probe as status/doctor. Nvim inspects cached plugins and language
  executables without starting the user's configuration or fetching components.
- Installation attempts retain their phase and outcome without overwriting
  successful install records; status and doctor show incomplete attempts.
  Progress/manifest write errors fail installation, and watchdog timeouts retain
  the last recorded phase. Status JSON adds a nullable `last_install` field.
- Provider failures now fail installation unless a later route supplies a
  verified tool; manual guidance no longer masks errors or stops fallback.
- Install and dry-run reject missing dependencies, dependency cycles, invalid
  module metadata, conflicting or nested links, and missing required link sources
  before changing tools or configuration.
- Cache cleanup preserves Neovim plugin installations and editor state, checks
  cache path boundaries, handles paths with spaces, and reports deletion errors.
- Failed uninstall operations retain their manifest entry and report unlink or
  state-removal errors instead of claiming completion.

[Unreleased]: https://github.com/gendu-amd/envup/tree/main
