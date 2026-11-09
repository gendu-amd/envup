# envup guide

[Quick start](../README.md) · [简体中文](../README.zh-CN.md) · [Contributing](../CONTRIBUTING.md)

## Commands

```text
envup install [-p PROFILE] [-n] [--tools reuse|locked] [MODULE...]
envup uninstall [--all] [-n] MODULE...
envup upgrade [-p PROFILE] [--ref TAG] [--tools reuse|locked] [-n] [-k]
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
  Missing dependencies, cycles, invalid module metadata, and conflicting link
  destinations (including nested links), and missing required link sources
  in this selection are rejected before installation; dry-run uses the same checks.
- A module ends as `ok`, `degraded`, `skipped`, or `failed`. Degraded means
  configuration is linked but the requested tool is unavailable, or the tool
  works with an incomplete selected component set. Skipped means not applicable.
  A zero install exit status can include degraded modules; inspect the result.
  Provider errors (such as download, checksum, extraction, or write failures)
  make installation fail unless a later route supplies a verified tool.
  Manual instructions do not erase earlier errors.
- `status` and `doctor` also show the last failed, interrupted, or incomplete
  install separately from current health. `status --json` adds `last_install`
  (or `null` for older records), with state, phase, reason, and time. A failed
  retry preserves the previous installed provider/version; a first failure
  does not mark the module installed. Retry with `envup install MODULE`.
- `status` probes the current filesystem and binaries instead of trusting the
  install manifest. `doctor --fix` repairs safe, known issues and checks again.
  `status` returning zero means the inspection ran; use its module states to
  judge readiness. `doctor --module NAME` checks just that module.
  Installation also checks final links and declared component health. JSON adds
  `check` with state/detail. Probes have a 15-second budget (`ENVUP_HEALTH_TIMEOUT`);
  without a timeout utility they warn and run without a watchdog.
  Nvim checks cached plugins, loadable selected parsers, and runnable language
  tools without loading your
  init or fetching anything; this does not verify plugin startup or language
  navigation. `ENVUP_NVIM_LAZY=skip` skips component checks for that invocation.
- `envup install zoxide atuin direnv delta` installs these tools independently
  of envup's shell/Git modules. The managed zsh configuration enables available
  shell integrations on its next load. For another shell, use each tool's init
  instructions. Delta refreshes pager defaults only for Git config managed by
  this checkout; existing private pager overrides keep precedence.
  A symlink at `~/.gitconfig.envup` is preserved and reported as an error; merge
  custom settings into `~/.gitconfig.local`, then remove just the symlink and retry.
- `upgrade` updates the checkout and reinstalls modules already in the manifest.
  Add `--profile` to pick up modules newly added to a profile, or `--ref <commit>`
  to pin a revision. Pulls require a fast-forward. Install runs with the selected
  checkout's CLI/libraries; a failed source update reports the actual revision,
  and `--keep-going` reinstalls that checkout while still returning failure.
  Checking out a tag leaves HEAD detached; return to your tracking branch before
  the next plain upgrade. Shared configuration links follow checkout changes
  immediately, even if the subsequent tool or plugin installation fails.
- `upgrade --tools reuse` (default) keeps runnable tools satisfying module
  requirements. `--tools locked` matches GitHub release modules to the dotted
  version in `versions.lock` or their compatibility `GH_TAG`; this can downgrade
  a newer tool. Matching tools are reused; otherwise only the GitHub release
  route is used, and an unavailable/wrong release fails the request. Other
  modules retain their normal providers. This does not pin system packages or
  language tools. `install --tools reuse|locked` uses the same policy;
  `ENVUP_TOOL_POLICY` supplies its default. Old checkouts lacking this option
  reject a locked upgrade request rather than silently reusing tools.
  Release installs warn if the caller's PATH selects another tool; put
  `ENVUP_LOCAL_BIN` first in your shell PATH to use the installed release.
- Successful installs record the resolved command path, checkout revision, and
  fetched release tag alongside the existing provider/version. `status --json`
  exposes them as `installed_tool`; old records have empty fields. These are
  installation snapshots; current health still probes the live machine.
- GitHub release installation stages and probes all commands before replacing
  existing files, then probes them again at the installed paths. A failed
  replacement restores the previous commands and runtime tree; if restoration
  fails, the error names the retained backup directory. This recovery covers
  the release files, not checkout changes, system packages, vendor scripts,
  plugin updates, concurrent installs, or an uncatchable process termination.
- `adopt` moves third-party lines appended through a managed symlink into
  `~/.zshrc.local`, then restores the tracked file.
- `clean` removes declared caches and reports unsafe paths or deletion errors.
  Nvim plugins, language tools, editor state, and private configuration are kept;
  rerun `envup install nvim` to restore pinned plugins and language tools.

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

Profiles are small Bash files in [`profiles/`](../profiles/). A custom profile can
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

Inside tmux, Nvim saves a checksum-marked `Session.vim` for crash recovery.
Existing user sessions, unmarked legacy sessions, symlinks and edited generated
sessions are preserved. Clean exits remove only this process's unchanged saves,
including saves made before changing directories. Disable saving with
`vim.g.envup_session = false` in your private Nvim configuration.

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

Copying also works in core mode and when plugin caches are missing. On WSL,
`clip.exe` is configured explicitly for Windows clipboard writes; this copy-only
provider pastes Nvim's local register, retaining characterwise, linewise and
blockwise selection types. Clipboard block width is inferred from the text;
extra virtual width beyond that text is not retained. A complete native provider
is used when available; otherwise OSC 52 sends copies to the outer terminal, including through
tmux. Enable OSC 52 writes in your terminal. OSC 52 does not read the terminal
clipboard, and received escape sequences alone cannot confirm an OS clipboard write.

Format-on-save runs only when the project contains a matching style file such as
`.clang-format`, `pyproject.toml`, or `.stylua.toml`. Set
`vim.g.envup_format_always = true` to always format. Large files (1.5 MB by
default) disable expensive editor features; set `vim.g.envup_bigfile_bytes = 0`
to disable that guard.

### Docker builds with host-side Nvim

clangd chooses the nearest project marker, such as `.clangd`,
`compile_commands.json` or `.git`. A parent workspace's `.clangd` no longer
overrides a nearer project database.

When Docker source/build paths differ from host paths, the generated
`compile_commands.json` needs translation. Matching absolute paths can avoid
this step when the compiler and headers are also available to host clangd.
For different paths, run from the host project root:

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

The sync command and Nvim must share `XDG_CACHE_HOME` and `NVIM_APPNAME`.
Restart Nvim if those variables change. Translation does not install a container's
toolchain or dependencies on the host.

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

Nvim uses a real `${XDG_CONFIG_HOME:-~/.config}/nvim` directory with links for
the shared config. `local.lua` stays in that user directory. Reinstalling an old
directory link to this checkout copies its `local.lua` into the user directory
and backs up the old link; it leaves the checkout copy untouched. Review and
remove that old private copy before sharing the checkout. Fresh installs never
import it. Directory links to other locations are preserved and require manual
migration before installation.

`doctor --fix --module nvim` uses the same local configuration preparation for
registered installations, without installing tools or plugins. It also prepares
a missing directory. Unregistered first failures are not adopted. Foreign or
unidentifiable dangling directory links require manual migration. Failed repairs
return failure even if the remaining config is usable; relocation records are
updated only after all repairs succeed. Keep backups and retry after resolving
the reported conflict; reverting code does not restore migrated user files.

Missing optional host/private Lua files are ignored. Existing files that fail to
load report their path and error in Nvim messages; editing and later overrides
continue. Errors in `envup.json` remain strict selection errors.

For core editing without plugins, create `envup.json` in that Nvim config directory
with `{"plugins": false}`. Install, startup and component checks all read this
private data file. Core mode uses Neovim's defaults and still loads host and
`local.lua` overrides; it keeps existing plugin data. Without this file, plugin
mode remains the default. Plugin bootstrap needs Git; core mode does not install it.

To select language support, use `{"languages": ["c", "cpp"]}` in the same file.
The selection controls language-tool installation/checks, LSP setup, formatters
and requested Treesitter parsers. Supported names are `c`, `cpp`, `python`, `lua`,
`bash` (including shell scripts), `json`, `yaml`, `markdown`, `html`, `css`, `vim`
and `vimdoc`; the last four only select parsers. Omitting `languages` keeps the
existing full set; `[]` selects none. Restart Nvim and run `envup install nvim`
after changing it. Existing tools/parsers are kept; unselected languages do not
request parser installation when a file is opened. Private Lua overrides can
still add their own support.

The checkout's `lazy-lock.json` is pinned input. Lazy writes its working lock in
Nvim's user state directory, keeping shared sources intact. Restore installations
reseed it from the pinned input before startup; sync keeps the working lock.
Lazy bootstrap is performed by `envup install nvim`; startup no longer clones
it automatically. With `ENVUP_NET=offline` or `ENVUP_OFFLINE=1`, startup uses
cached plugins and disables automatic Lazy, Mason and Treesitter installation.
Missing plugins or required generated theme files fall back to core editing
with a diagnostic; host/private overrides still load. Offline installation
checks cached components without restore/sync or deleting incomplete caches.
These controls cover envup startup/install; manually invoked plugin commands
and private overrides retain their own behavior.

The Bash-to-zsh entry block installed by the zsh module requires a real `~/.bashrc` file. Envup
preserves existing rc symlinks and reports an error rather than appending through
them; keep the shell entry in your own configuration or migrate the rc file first.

Git records its generated defaults in the machine state directory. Reinstalling
backs up an existing unrecorded or edited `~/.gitconfig.envup`; uninstall removes
only output that still exactly matches that record. Legacy output without a record
is preserved. Keep settings you want to retain in `~/.gitconfig.local`.

For example, copy `modules/tmux/files/hosts/example.conf.template` to the current
hostname and rerun `envup install tmux`. Keep credentials and throwaway settings
only in the private layer outside the repository.

## Environment variables

All are optional.

Lazy applies the GitHub mirror through Git parameters inherited by this Nvim
process. Plugin URLs and saved origins stay canonical, and Git configuration
files are untouched. Export the variable before starting Nvim. This covers
Lazy's Git transport and Mason's GitHub registry archives and Release assets.
Mason metadata services and npm/pip packages retain their own routes.
Treesitter installs missing or unusable selected parsers synchronously through
Git, which inherits the mirror routing. Startup and plugin restore do not
automatically download or update parsers; usable existing parsers are reused.
Installation and read-only health checks load the parsers to check availability,
without claiming to verify their exact version or every editing feature.
Mason language tools and Treesitter parsers are installed explicitly by
`envup install nvim`, rather than on LSP configuration load. That headless step
uses `ENVUP_NET_TIMEOUT_NVIM` when a timeout utility is available; errors and
timeouts fail the command and keep components already installed for a retry.
Lazy restore/sync also checks task errors, missing plugins and configuration
errors; a failure stops the later language-tool and parser installation steps.

| Variable | Default | Purpose |
|---|---|---|
| `ENVUP_DRY_RUN` | `0` | Preview changes; the CLI `--dry-run` flag sets it. |
| `ENVUP_OFFLINE` | `0` | Skip network attempts while still installing configuration. |
| `ENVUP_GH_MIRROR` | — | Prefix for GitHub release, clone, and raw URLs, including Lazy Git transport and Mason GitHub assets. |
| `ENVUP_REQUIRE_CHECKSUM` | `0` | Refuse downloads without a matching published checksum. |
| `ENVUP_LOCAL_BIN` | `~/.local/bin` | User-space binaries; shared HOME defaults to `~/.local/envup/hosts/<host>/bin`. |
| `ENVUP_LOCAL_OPT` | `~/.local/opt` | Full application trees; shared HOME defaults to `~/.local/envup/hosts/<host>/opt`. |
| `ENVUP_BACKUP_DIR` | timestamped directory | Backup root for replaced link targets. |
| `ENVUP_STATE_DIR` | `~/.local/state/envup` | Manifest, logs, and adopt state; host-scoped on shared HOME. |
| `ENVUP_LOG_DIR` | `$ENVUP_STATE_DIR/logs` | Log directory. |
| `ENVUP_LOG_FILE` | timestamped file | Current command log; use `/dev/null` to disable. |
| `ENVUP_LOG_LEVEL` | `info` | Terminal verbosity: `debug`, `info`, `warn`, or `error`. |
| `ENVUP_MODULE_TIMEOUT` | `900` | Watchdog seconds for each module hook. |
| `ENVUP_NET_TIMEOUT` | `120` | Timeout seconds for each Git operation. |
| `ENVUP_NET_TIMEOUT_NVIM` | `600` | Budget per headless Nvim install step; Lazy Git operations use the smaller of this and `ENVUP_NET_TIMEOUT` (positive integer seconds). |
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

## Maintenance and troubleshooting

### Inspect, update and remove

```bash
envup status                        # current tools, links and components
envup doctor --module nvim          # inspect one module
envup doctor --fix                  # repair managed parts and check again
envup upgrade --tools reuse         # fast-forward checkout; reinstall recorded modules
envup uninstall git --dry-run       # preview removal
envup uninstall git                 # remove managed integration; retain user data
envup log                          # latest operation log
```

For a first lifecycle check, install Git alone. Set `user.name`, `user.email`
and any aliases with `git config --file "$HOME/.gitconfig.local" ...`, then
verify them with `git config --global --includes --get user.name`.
Private settings survive reinstall, upgrade and uninstall. Removing managed
`~/.gitconfig` also removes its includes from active Git config. Uninstall keeps
binaries and backups; it does not automatically restore pre-install files.
Review the backup before restoring it.

- Missing bundled shell/tmux plugins: `git submodule update --init --recursive`,
  then reinstall the module. Full `doctor --fix` can also fetch missing submodules;
  `--module NAME` restricts module repair and omits repository-wide repair.
- Moved checkout or broken links: run `envup doctor --fix` from the new location.
- Appended managed files: use `envup adopt` before upgrading.
- Inconsistent Nvim plugins: rerun `envup install nvim` to restore pinned plugins.
  `clean nvim` removes declared caches, preserving plugins and language tools.
- Mason Python errors such as `no such option: --no-user`: select a compatible
  `python3`/pip on PATH and retry. Envup does not install or upgrade Python/pip.
- Missing timeout utility: install one to bound probes/hooks (macOS: `brew install
  coreutils`). Without one, envup warns and some steps run without a watchdog.
- Busy manifest after interruption: inspect the reported lock and active writers
  before removing leftovers. A dead PID alone does not prove lock ownership.
- Degraded module: inspect its reason, supply missing prerequisites or retry when
  a provider becomes available. Check current health before calling it ready.

Module hooks receive detected `ENVUP_OS`, `ENVUP_PLATFORM`, `ENVUP_DISTRO`,
`ENVUP_DISTRO_VER`, `ENVUP_DISTRO_LIKE`, `ENVUP_ARCH`, `ENVUP_LIBC`,
`ENVUP_PRIV`, `ENVUP_PKG`, `ENVUP_NET`, `ENVUP_HOST` and `ENVUP_HOME_SHARED`.
Treat them as read-only facts; only `ENVUP_PLATFORM` is a supported user override.

On shared HOME, distinct short hostnames scope envup tool/state directories.
Explicit `ENVUP_LOCAL_BIN`/`ENVUP_LOCAL_OPT` remain authoritative; unscoped tools
stay in place. Other shells need the reported host binary directory on PATH.
This does not isolate every third-party plugin cache or user data directory.

### Functional and platform acceptance

After installation, open a fresh terminal and exercise the selected workflow:

| Capability | Functional check |
|---|---|
| Shell | Try `z`, `Ctrl-r` and `Ctrl-t`. |
| Git | Confirm private identity and run `git diff`. |
| tmux | Create panes, copy to the outer terminal, save/restore a disposable session. |
| Nvim | Edit/save a scratch file; test selected language definitions, diagnostics and project-enabled formatting. |
| Host Nvim + Docker builds | Restart the LSP after syncing and verify a real project definition. |

Install success and component health do not prove terminal clipboard access,
plugin startup or project navigation. Navigation requires the project's toolchain,
headers and compilation database; clipboard access requires the actual outer terminal.

| Environment | Verified coverage and limits |
|---|---|
| Linux x86_64 server | Isolated-HOME default tools/plugins/languages, clangd navigation and the install/update/removal lifecycle were checked. |
| macOS ARM64; Ubuntu, Debian 11, Fedora, Arch, Alpine | CI checks Git lifecycle and a runnable pinned zoxide release. |
| No-root Docker; offline | CI exercises standard no-root and minimal offline configuration respectively. |
| Bash 4.0 / 4.2 | Local 4.0 CLI/offline Git lifecycle and CI 4.2 configuration deployment; not a full tool installation matrix. |
| WSL2 | Detection/clipboard fixtures; real Windows clipboard use remains unverified. |
| Shared HOME | Simulated glibc/musl host isolation; real NFS/SMB and cross-CPU sharing remain unverified. |

Full Nvim language/plugin support is not accepted on every platform. Package and
release availability varies. See [Contributing](../CONTRIBUTING.md) for architecture,
module contracts and checks, and [CHANGELOG](../CHANGELOG.md) for changes.
