# envup

> One repo and one CLI for a consistent terminal development environment.

[![CI](https://github.com/gendu-amd/envup/actions/workflows/ci.yml/badge.svg)](https://github.com/gendu-amd/envup/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-yellow.svg)](LICENSE)
![Platforms](https://img.shields.io/badge/platform-macOS%20%7C%20Linux%20%7C%20WSL2%20%7C%20Docker-blue)

**English** | [简体中文](README.zh-CN.md)

envup installs and manages shell, editor, tmux, and CLI tooling as independent
modules. It is designed for both workstations and restricted servers: existing
dotfiles are backed up, no-root and offline installs degrade cleanly, and every
change is inspectable and reversible.

## Requirements

- Bash 4.0 or newer. On macOS, install a current Bash with `brew install bash`;
  envup finds it automatically.
- Git 2.0 or newer.
- macOS, Linux, WSL2, or Docker.

Root, a package manager, and network access are optional. Without them, envup
still links configuration and installs any compatible user-space releases it
can obtain.

## Quick start

```bash
git clone --recursive https://github.com/gendu-amd/envup.git
cd envup
./envup install                 # standard profile
# ./envup install --profile full
# ./envup install nvim tmux     # selected modules only
exec zsh
```

If the repository was cloned without submodules:

```bash
git submodule update --init --recursive
```

Use `./envup` inside the checkout or `envup` after installing the zsh module.

## Commands

```text
envup install [-p PROFILE] [-n] [MODULE...]
envup uninstall [--all] [-n] MODULE...
envup upgrade [-p PROFILE] [--ref TAG] [-n] [-k]
envup status [--json]
envup doctor [--fix] [--authoring] [--module NAME]
envup adopt [-n] [PATH...]
envup clean [-n] [--all | MODULE...]
envup clangd <sync|status|clean> [options]
envup log [--tail]
envup version
```

Run `envup <command> --help` for all options.

- `install --profile X MODULE...` installs the union of the profile and named
  modules. Dependencies are ordered and duplicate modules are removed.
- A module ends as `ok`, `degraded`, `skipped`, or `failed`. Degraded means its
  configuration is ready but the tool cannot be installed on this machine;
  only failed makes the command fail.
- `status` probes the current filesystem and binaries instead of trusting the
  install manifest. `doctor --fix` repairs safe, known issues and checks again.
- `upgrade` updates the checkout and reinstalls modules already in the manifest.
  Add `--profile` to pick up modules newly added to a profile, or `--ref v0.1.0`
  to pin a release.
- `adopt` moves third-party lines appended through a managed symlink into
  `~/.zshrc.local`, then restores the tracked file.
- `clean` removes declared caches, never user data or configuration.

## Profiles and modules

| Profile | Contents | Intended use |
|---|---|---|
| `minimal` | zsh, git | containers and bare servers |
| `standard` | minimal + terminal and search tools | default workstation/server setup |
| `full` | standard + nvim, lazygit, yazi | complete terminal IDE |

| Module | Function |
|---|---|
| `zsh` | Oh-My-Zsh, Powerlevel10k, completions, aliases, Vi command line |
| `git` | Safe global defaults and optional delta integration |
| `tmux` | Multiplexing, project sessions, OSC 52 copy, session restore |
| `fzf` | Fuzzy files, directories, history, and completion |
| `ripgrep` | Fast recursive text search with `.gitignore` support |
| `fd` | Friendly file search used by fzf |
| `bat` | Syntax-highlighted `cat` and previews |
| `eza` | Modern `ls`, tree, icons, and Git status |
| `zoxide` | Frecency-based `z` and interactive `zi` directory jumps |
| `atuin` | SQLite-backed, fuzzy shell history |
| `delta` | Readable syntax- and word-aware Git diffs |
| `direnv` | Per-directory environment from trusted `.envrc` files |
| `jq` | JSON processing for APIs, logs, and pipelines |
| `tealdeer` | Fast example-oriented help through `tldr` |
| `nvim` | Neovim + NvChad, pinned plugins, LSP, formatting, sessions |
| `lazygit` | Terminal UI for Git history, staging, branches, and rebases |
| `yazi` | Fast terminal file manager; `y` keeps its final directory |

Profiles are small Bash files in [`profiles/`](profiles/). A custom profile can
reuse another profile and append modules:

```bash
# profiles/work.sh
use_profile standard
MODULES+=(nvim lazygit)
```

## Daily shortcuts

`prefix` below means tmux's `Ctrl-a`.

| Action | Key or command |
|---|---|
| zsh insert → normal → insert | `Esc`, then `i` or `a` |
| Fuzzy history / files / directories | `Ctrl-r` / `Ctrl-t` / `Alt-c` |
| Jump to a known or selected directory | `z name` / `zi` |
| Resume sessions / choose a project | `tm` / `ts`, or `prefix f` |
| Move through tmux panes and Nvim splits | `Ctrl-h/j/k/l` |
| Split tmux horizontally / vertically | `prefix -` / `prefix |` |
| Move the current tmux window and follow it | `prefix <` / `prefix >` |
| Enter tmux copy mode | `prefix v`; move with `hjkl`, select `v`, copy `y`, cancel `i` |
| Open Nvim horizontal / vertical terminal | `Space h` / `Space v` |
| Toggle Nvim horizontal / vertical / floating terminal | `Alt-h` / `Alt-v` / `Alt-i` |
| Leave Nvim terminal input / list hidden terminals | `Ctrl-x` / `Space pt` |
| Open lazygit / Yazi | `lg` / `y` |
| Practical command examples | `tldr command` (`tldr --update` once if needed) |

Tmux and Nvim use OSC 52 so copied text can reach the terminal on your local
machine over SSH. VS Code and Cursor require
`terminal.integrated.enableClipboardWrite: true`. Native clipboard tools such as
`pbcopy`, `wl-copy`, `xclip`, or `clip.exe` are preferred when available.

Sessions are saved every five minutes. `tm` starts tmux, waits for restoration,
and attaches to the recovered session. Project roots for `ts`/`prefix f` default
to common directories such as `~/work`, `~/src`, and `~/projects`; override them
with `ENVUP_PROJECT_DIRS` or `~/.config/envup/project-dirs`.

## Nvim

The nvim module requires Neovim 0.10+. On older-glibc Linux hosts, envup uses a
compatible v0.10 release instead of a binary that cannot start. Conda is another
reliable option: `conda install -c conda-forge neovim`.

Installed language tooling:

| Language | LSP | Formatter |
|---|---|---|
| C / C++ | clangd | clang-format |
| Python | pyright | Ruff |
| Lua | lua-language-server | StyLua |
| shell | bash-language-server | shfmt |
| JSON / YAML / Markdown | — | Prettier |

| Action | Key |
|---|---|
| Definition / declaration | `gd` / `gD` |
| References / implementation / type definition | `gr` / `gi` / `gy` |
| Hover / signature | `K` / `Space lh` |
| Rename / code action | `Space rn` / `Space ca` |
| File / workspace symbols | `Space ls` / `Space lS` |
| Previous / next / full diagnostic | `[d` / `]d` / `Space df` |
| Format manually | `Space fm` |

Press `K` again to focus a hover window, `K` or `Ctrl-w p` to return to source,
and `Esc` to close it. Navigation reports when no suitable LSP or result exists.

Format-on-save runs only when the project contains a matching style file such as
`.clang-format`, `pyproject.toml`, or `.stylua.toml`. Set
`vim.g.envup_format_always = true` to always format. Large files (1.5 MB by
default) disable expensive editor features; set `vim.g.envup_bigfile_bytes = 0`
to disable that guard.

### Docker builds with host-side Nvim

A Docker-generated `compile_commands.json` contains container paths, so host
clangd cannot use it directly. From the host project root run:

```bash
envup clangd sync
envup clangd status
# use --container NAME only if automatic container selection is ambiguous
```

envup reads Docker mount mappings, translates a cached copy, and leaves the
original build tree untouched. Run `:LspRestart` after syncing. Repeat the sync
after reconfiguring the Docker build; Nvim warns when the source database becomes
stale. Use `envup clangd sync --database PATH` when the database is outside the
usual project/build locations.

## Configuration model

Managed files are symlinked from each module's `files/` directory. An existing
target is moved to `~/.dotfiles_backup/<timestamp>/` with its relative path
preserved. Reinstalling is idempotent; uninstall removes only links owned by this
checkout.

Machine-specific, shareable configuration uses the shipped host templates:

| Module | Version-controlled host layer | Private final override |
|---|---|---|
| zsh | `modules/zsh/files/.zshrc.d/hosts/<host>.zsh` | `~/.zshrc.local` or `~/.zshrc.local.<host>` |
| tmux | `modules/tmux/files/hosts/<host>.conf` | `~/.tmux.local` |
| nvim | `modules/nvim/files/hosts/<host>.lua` | `~/.config/nvim/local.lua` |
| git | `modules/git/files/hosts/<host>.gitconfig` | `~/.gitconfig.local` |

For example, copy `modules/tmux/files/hosts/example.conf.template` to the current
hostname and rerun `envup install tmux`. Keep credentials and throwaway settings
only in the private layer outside the repository.

## Environment variables

All are optional.

| Variable | Default | Purpose |
|---|---|---|
| `ENVUP_DRY_RUN` | `0` | Preview changes; the CLI `--dry-run` flag sets it. |
| `ENVUP_OFFLINE` | `0` | Skip network attempts while still installing configuration. |
| `ENVUP_GH_MIRROR` | — | Prefix for GitHub release, clone, and raw URLs. |
| `ENVUP_REQUIRE_CHECKSUM` | `0` | Refuse downloads without a matching published checksum. |
| `ENVUP_LOCAL_BIN` | `~/.local/bin` | User-space binary destination. |
| `ENVUP_LOCAL_OPT` | `~/.local/opt` | User-space destination for full application trees. |
| `ENVUP_BACKUP_DIR` | timestamped directory | Backup root for replaced link targets. |
| `ENVUP_STATE_DIR` | `~/.local/state/envup` | Manifest, logs, and adopt state; host-scoped on shared HOME. |
| `ENVUP_LOG_DIR` | `$ENVUP_STATE_DIR/logs` | Log directory. |
| `ENVUP_LOG_FILE` | timestamped file | Current command log; use `/dev/null` to disable. |
| `ENVUP_LOG_LEVEL` | `info` | Terminal verbosity: `debug`, `info`, `warn`, or `error`. |
| `ENVUP_MODULE_TIMEOUT` | `900` | Watchdog seconds for each module hook. |
| `ENVUP_NET_TIMEOUT` | `120` | Timeout seconds for each Git operation. |
| `ENVUP_NET_TIMEOUT_NVIM` | `600` | Timeout for Nvim plugin restoration. |
| `ENVUP_NET_TIMEOUT_INSTALLER` | `300` | Timeout for vendor install scripts. |
| `ENVUP_NET_KILL_AFTER` | `10` | Grace period between timeout and forced termination. |
| `ENVUP_NET_PROBE_TIMEOUT` | `5` | Network capability probe timeout. |
| `ENVUP_PRIV_KEEP_ENV` | auto | Force (`1`) or disable (`0`) `sudo -E`. |
| `ENVUP_EDITOR` | auto | Preferred editor candidate before nvim/vim/vi/nano. |
| `ENVUP_PLATFORM` | auto | Override with `macos`, `linux`, `wsl2`, or `docker`. |
| `ENVUP_NVIM_LAZY` | `restore` | `restore`, `sync`, or `skip` Nvim plugin installation. |
| `ENVUP_ATUIN_INSTALL` | — | Set to `skip` to omit Atuin. |
| `ENVUP_ZSH_QUIET` | `0` | Suppress zsh slice-load warnings. |
| `ENVUP_PROJECT_DIRS` | common roots | Colon-separated globs for project selection. |
| `ENVUP_TMUX_SESSION` | `main` | Session created when nothing can be restored. |
| `ENVUP_TMUX_RESTORE_WAIT` | `8` | Seconds `tm` waits for restore. |
| `ENVUP_TS_POPUP` | auto | Force (`1`) or disable (`0`) tmux popup selection. |

## Reliability and troubleshooting

The install engine detects OS, distribution, architecture, libc, privilege,
package manager, and network capability. Providers are tried in order: system
package, compatible GitHub release, Git/vendor installer, then a manual hint.
Downloads, package operations, and module hooks have timeouts. State-changing
commands write logs under `$ENVUP_STATE_DIR/logs`.

Detection results are exported to module hooks as `ENVUP_OS`, `ENVUP_PLATFORM`,
`ENVUP_DISTRO`, `ENVUP_DISTRO_VER`, `ENVUP_DISTRO_LIKE`, `ENVUP_ARCH`,
`ENVUP_LIBC`, `ENVUP_PRIV`, `ENVUP_PKG`, `ENVUP_NET`, `ENVUP_HOST`, and
`ENVUP_HOME_SHARED`. Treat them as read-only facts; only `ENVUP_PLATFORM` is a
supported user override.

```bash
envup doctor                 # explain local problems
envup doctor --fix           # repair and re-check
envup log                    # latest operation log
ENVUP_LOG_LEVEL=debug envup install nvim
```

Common fixes:

- Missing theme/plugins: `git submodule update --init --recursive`, then reinstall.
- Repo moved or links dangle: run `envup doctor --fix` from the new checkout.
- Managed files were appended to: run `envup adopt` before upgrading.
- Nvim plugins are inconsistent: `envup clean nvim && envup install nvim`.
- No timeout command on macOS: `brew install coreutils` supplies `gtimeout`.
- A module is degraded: install the named system prerequisite or rerun when
  network/root access is available; its configuration is already linked.

Supported and CI-covered paths include macOS, Ubuntu/Debian, Fedora/CentOS,
WSL2, Docker, no-root, offline, and Bash 4.2. Arch and Alpine are supported on a
best-effort basis; platform-specific package availability still varies.

## Architecture and development

`envup` dispatches commands; [`lib.sh`](lib.sh) loads focused libraries for
capability detection, filesystem safety, networking, providers, module planning,
health, and upgrades. A module contains declarative `meta.sh`, optional function-
based `hooks.sh`, and symlinked `files/`. Profiles only compose module names.

See [CONTRIBUTING.md](CONTRIBUTING.md) for the module contract, checks, and release
steps, and [CHANGELOG.md](CHANGELOG.md) for release notes.

## License

MIT — see [LICENSE](LICENSE).
