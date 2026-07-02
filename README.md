# envup

> One repo, one CLI, one command — cross-platform development environment.

[![CI](https://github.com/gendu-amd/envup/actions/workflows/ci.yml/badge.svg)](https://github.com/gendu-amd/envup/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
![Platforms](https://img.shields.io/badge/platform-macOS%20%7C%20Linux%20%7C%20WSL2%20%7C%20Docker-blue)
![Shell](https://img.shields.io/badge/shell-bash%20%E2%89%A5%204-green)

**English** | [简体中文](README.zh-CN.md)

A modular dotfiles manager that lets you set up your shell, editor, and CLI tools on any new machine with a single command. Pick a profile (minimal / standard / full) or install individual modules; uninstall anything you don't want; everything is logged and reversible.

## Requirements

- **bash ≥ 4.0** (associative arrays for module dependency resolution). On **macOS**, `/bin/bash` is still 3.2 — run `brew install bash` once; `envup` auto-detects Homebrew's bash when you `./envup` (your login shell / tmux shell can stay zsh).
- **git ≥ 2.0** (submodule rename support; almost certainly already installed)
- **A POSIX system**: macOS, Linux (Ubuntu/Debian/Fedora/CentOS/Arch/Alpine), WSL2, or Docker
- **A package manager**: apt / dnf / yum / pacman / brew / apk
- **Network access** for first-time install (downloads zsh plugins, optional curl-installed tools like atuin/fzf)
- **`sudo` available** if any system packages are missing (you'll see the prompt)
- **Recommended**: `~/.local/bin` on `$PATH` so `envup` is globally accessible after install

## Quick Start

```bash
# Clone (with submodules — required for zsh themes/tmux plugins)
git clone --recursive https://github.com/gendu-amd/envup.git
cd envup

# Forgot --recursive? Catch up:
#   git submodule update --init --recursive

# Install the standard profile (zsh, git, tmux, fzf, zoxide, atuin)
./envup install

# ... or pick a smaller profile
./envup install --profile minimal

# ... or install just what you need
./envup install zsh git

# Start a new shell
exec zsh
```

## What it looks like

```console
$ ./envup install --profile standard
[i] install order: zsh git tmux fzf zoxide atuin
==> [zsh] install
✓ linked: ~/.zshrc
...
✓ installed: zsh git tmux fzf zoxide atuin

$ ./envup status
[i] Platform: linux (x86_64)  PkgMgr: dnf
Modules:
  ✓ zsh      Modern shell with Oh-My-Zsh + Powerlevel10k theme
  ✓ git      Git config (~/.gitconfig with delta as pager)
  ○ nvim     Neovim editor with NvChad config + lazy.nvim plugins
  ...

$ ./envup status --json | jq '.modules[] | select(.installed)'
{ "name": "zsh", "description": "Modern shell ...", "installed": true }
```

> Prefer a recorded terminal cast? Generate one locally with
> [asciinema](https://asciinema.org): `asciinema rec` while you run the commands
> above, then link the resulting cast here.

## Commands

```bash
./envup install [--profile NAME] [--dry-run] [MODULE...]                    # Install
./envup uninstall [--all] [--dry-run] MODULE...                             # Remove
./envup upgrade [--profile NAME] [--ref TAG] [--dry-run] [--keep-going] ...  # update + reinstall
./envup status [--json]                                                     # What's installed (✓ / ○)
./envup clean [--dry-run] [--all | MODULE...]                               # Clear caches (meta CLEAN_PATHS)
./envup log [--tail]                                                        # Most recent command's log
./envup doctor [--module NAME]                                             # Validate module conventions
./envup --version                                                          # Print the envup version
```

Use `./envup <command> --help` for command-specific options.

A few important semantics that aren't obvious from the one-liners:

- `install --profile X MODULE...` is a **UNION**, not OR — `envup install --profile minimal nvim` installs minimal's modules **and** nvim, deduped.
- `upgrade` by default only reinstalls modules **already in your manifest** (`~/.local/state/envup/installed`). If your team added a new module to a profile, pass `--profile NAME` to pick it up.
- `upgrade --ref v0.1.0` checks out a specific tag/branch (fetch + checkout + submodules) instead of pulling the current branch — use it to pin or roll to a released version.
- `status --json` prints machine-readable state (platform, package manager, modules with `installed` flags, profiles) for scripting.
- `ENVUP_LOG_LEVEL=debug|info|warn|error` (default `info`) controls terminal verbosity; the log file always records everything.
- `ENVUP_GH_MIRROR=https://ghproxy.com` routes envup's own GitHub downloads (lazy.nvim, fzf, oh-my-zsh, zoxide installers, and nvim's first-launch bootstrap) through a mirror/proxy — handy on restricted networks. Unset = unchanged. For the git **submodules** (zsh/tmux plugins), use git's own redirect: `git config --global url."https://ghproxy.com/https://github.com/".insteadOf https://github.com/`.
- `envup doctor` statically validates every module (meta fields, function-wrapped hooks, valid `DEPENDS`, and that `CLEAN_PATHS` never targets user data) — run it after adding a module.
- **No step can hang the whole run:** network calls and the package manager are wrapped in timeouts, and each module hook runs under an outer watchdog (`ENVUP_MODULE_TIMEOUT`, default 900s). A stuck module is killed and reported failed; install continues with the rest. (Needs a `timeout`/`gtimeout` binary — on macOS: `brew install coreutils`.)
- `upgrade --keep-going` lets the run continue even if `git pull` failed; otherwise upgrade aborts to avoid silently reinstalling stale config.
- `upgrade --dry-run` skips `git pull` entirely and forwards `--dry-run` to install.
- `clean` removes module-managed plugin caches (lazy.nvim, mason, oh-my-zsh, etc.) — NOT the binary, NOT your config. Useful when nvim Lazy state gets weird.
- `log` shows the **most recent** command's log (install, uninstall, upgrade, or clean — whichever ran last).

## Profiles

| Profile | Modules | Use case |
|---------|---------|----------|
| `minimal` | `zsh git` | Bare server, headless container |
| `standard` (default) | `+ tmux fzf zoxide atuin` | Typical developer workstation |
| `full` | `+ nvim` | Power-user workstation |

Profiles are just bash files at [`profiles/`](profiles/) — easy to read, easy to add your own:

```bash
# profiles/myown.sh
MODULES=(zsh git tmux atuin)
```

Then `./envup install --profile myown`.

Profiles **compose** with `use_profile` so each layer only states what it adds
(no restating the whole list):

```bash
# profiles/minimal.sh
MODULES+=(zsh git)

# profiles/standard.sh  (default) = minimal + terminal tooling
use_profile minimal
MODULES+=(tmux fzf zoxide atuin)

# profiles/full.sh = standard + editor
use_profile standard
MODULES+=(nvim)
```

Want a bigger set? Either `use_profile` an existing one and append, or union on
the CLI: `./envup install --profile standard nvim`.

## Modules

Each module is a self-contained directory under [`modules/`](modules/) with three files:

```
modules/<name>/
├── meta.sh          # Declares NAME, DESCRIPTION, DEPENDS=(...)
├── install.sh       # Hook: install package + symlink configs
├── uninstall.sh     # Hook: remove envup-managed symlinks
└── files/           # Config files (symlinked to ~/)
```

Adding a new tool = creating a new directory. No registry, no config update.

| Module | Tool | Depends |
|--------|------|---------|
| `zsh` | Modern shell with Oh-My-Zsh + Powerlevel10k (also makes zsh your default shell) | — |
| `git` | Git config (with delta as pager) | — |
| `tmux` | Terminal multiplexer (new panes use zsh) | — |
| `fzf` | Fuzzy finder (Ctrl+T / Ctrl+R) | — |
| `zoxide` | Smarter `cd` — `z <dir>` to jump, `zi` to pick | `zsh` |
| `atuin` | SQLite-backed shell history | `zsh` |
| `nvim` | Neovim with NvChad (plugins pinned via lazy-lock.json) | — |

### Default shell

The `zsh` module makes zsh the shell you actually land in, on three fronts:

1. `chsh` changes your login shell (effective next login).
2. On accounts where `chsh` is blocked (LDAP/SSSD-managed corp/HPC boxes), a
   small guarded block is added to `~/.bashrc` that `exec`s zsh for interactive
   bash. Escape hatch: `NO_ZSH=1 bash`.
3. The `tmux` module sets `default-command zsh`, so new panes use zsh
   regardless of the system login shell.

`envup uninstall zsh` removes the `~/.bashrc` block (it leaves the `chsh`
setting alone).

### nvim module

The `nvim` module symlinks the NvChad config to `~/.config/nvim` and installs
plugins. NvChad needs **nvim >= 0.10**; if your distro's nvim is older, the hook
stops and prints upgrade options (envup never touches your system package
sources):

```bash
brew install neovim                          # macOS
conda install -c conda-forge neovim          # old-glibc systems (RHEL/CentOS 8, …)
# or build from source: https://github.com/neovim/neovim/blob/master/BUILD.md
```

**Reproducible plugins.** The plugin set is pinned by a committed
`lazy-lock.json`, validated to load on both nvim 0.10 (old-glibc hosts) and
0.11 (containers). `envup install nvim` *restores* exactly those versions, so
every machine gets the same editor. Control it with `ENVUP_NVIM_LAZY`:

- `restore` (default) — install the pinned versions from `lazy-lock.json`.
- `sync` — update plugins to latest within spec **and rewrite the lock**; commit
  the new `lazy-lock.json` afterwards to roll it out everywhere.
- `skip` — leave plugins for nvim's first interactive launch.

`./envup clean nvim` clears plugin/cache state if it gets stuck; the next
install restores from the lock.

## How It Works

```
┌─────────────────────────────────────────────────────┐
│  ./envup install --profile standard                   │
│         ↓                                           │
│  load profiles/standard.sh → MODULES=(zsh git ...)  │
│         ↓                                           │
│  resolve order (each module's DEPENDS first)        │
│         ↓                                           │
│  for each module:                                   │
│    source modules/<m>/install.sh                    │
│    safe_link <repo files> → ~/                      │
│    record in ~/.local/state/envup/installed           │
│         ↓                                           │
│  log to ~/.local/state/envup/logs/install_<ts>.log    │
└─────────────────────────────────────────────────────┘
```

Key properties:

- **Idempotent**: Re-running `./envup install` is safe. Existing symlinks are detected and skipped.
- **Reversible**: Every overwritten file is backed up to `~/.dotfiles_backup/<timestamp>/`. `./envup uninstall` removes only envup-managed symlinks.
- **Loggable**: Every command writes a timestamped log under `~/.local/state/envup/logs/`. Use `./envup log --tail` to follow live.
- **Cross-platform**: macOS, Linux (apt/dnf/yum/pacman/brew/apk), WSL2, Docker. Auto-detects the platform and package manager.

## Environment Variables

envup recognises these env vars at install time. All are optional; defaults are sensible for the common case.

| Variable | Default | Effect |
|---|---|---|
| `ENVUP_DRY_RUN` | `0` | When `1`, every destructive step prints what it would do without changing anything. `--dry-run` sets this automatically. |
| `ENVUP_NVIM_LAZY` | `restore` | `restore` installs the pinned versions from `lazy-lock.json`; `sync` updates to latest and rewrites the lock; `skip` leaves them for nvim's first launch. |
| `ENVUP_ATUIN_INSTALL` | — | Set to `skip` to skip the atuin module (handy when its installer is blocked by a network/proxy). |
| `ENVUP_NET_TIMEOUT` | `120` | Per-command timeout for git operations. Falls back gracefully when `timeout(1)` is unavailable (macOS: `brew install coreutils` for `gtimeout`). |
| `ENVUP_NET_TIMEOUT_NVIM` | `600` | Larger timeout for `nvim --headless +Lazy!` (cloning 30+ plugins takes minutes). |
| `ENVUP_NET_TIMEOUT_INSTALLER` | `300` | Timeout for `curl ... \| sh` installers (Oh-My-Zsh, atuin, zoxide). |
| `ENVUP_NET_KILL_AFTER` | `10` | Grace period (s) after a network timeout before the process is SIGKILLed, so a wedged connection can't hang past the budget. |

Docker example:

```bash
docker run -it --rm ubuntu:24.04 bash -c '
    apt-get update && apt-get install -y git ca-certificates &&
    git clone --recursive https://github.com/gendu-amd/envup.git /opt/envup &&
    /opt/envup/envup install --profile standard
'
```

### Pre-existing dotfiles

If a link target is an existing **real file** (e.g. a `~/.zshrc` you wrote by
hand), envup **always backs it up** to `~/.dotfiles_backup/<timestamp>/` before
creating the symlink — it never silently overwrites your files. To restore one,
move it back from that directory.

## Logs and Troubleshooting

```bash
./envup log              # show the latest log (install/uninstall/upgrade/clean)
./envup log --tail       # follow live (useful for long installs)

# Logs persist at:
ls ~/.local/state/envup/logs/
```

If something fails:
1. Check the log — every command's exit code, duration, and any stderr is captured.
2. Re-run with `--dry-run` to see what would happen without doing anything.
3. The hook script for the failing module is at `modules/<name>/install.sh` — read it, edit it locally, retry.

### Common issues

**`./envup install` fails on a minimal docker image** — envup installs each selected module's declared `SELF_DEPS` (e.g. `curl`, `git`) up front. If that fails (e.g. apt repos blocked), install those packages manually then re-run.

**zsh prompt is plain / Powerlevel10k missing** — you probably forgot `--recursive` when cloning. Fix:
```bash
git submodule update --init --recursive
./envup install zsh
```

**`bash: warning: setlocale: cannot change locale (en_US.UTF-8)`** — envup runs `locale-gen` on apt systems automatically; if you see it persist, run `sudo locale-gen en_US.UTF-8` manually.

**`envup: command not found` after install** — the `zsh` module symlinks `envup` to `~/.local/bin/envup`. Make sure `~/.local/bin` is on `$PATH` (login again, or `exec zsh`).

**`nvim too old` error** — NvChad needs nvim >= 0.10 and envup does NOT touch your APT sources. Upgrade via `brew install neovim`, `conda install -c conda-forge neovim` (best on old-glibc systems like RHEL/CentOS 8), or a source build, then re-run `envup install nvim`.

**nvim Lazy plugins corrupt / want a clean state** — `./envup clean nvim` clears the plugin cache and Mason LSP servers without touching your config; the next `./envup install nvim` restores the pinned plugin set from `lazy-lock.json`.

**`envup install` / `upgrade` hangs forever on a slow/blocked network** — every network operation (git pull, git clone, submodule update, nvim Lazy) is wrapped with a per-command timeout (default 120s for git, 600s for Lazy). On hit you'll see a `TIMED OUT after Ns` error and a hint to raise `ENVUP_NET_TIMEOUT=...` / `ENVUP_NET_TIMEOUT_NVIM=...`. Behind a slow proxy / VPN? `ENVUP_NET_TIMEOUT=300 ./envup upgrade`.

**timeout warning on macOS** — log line `no 'timeout' command on this system` means your install isn't protected against hung git/curl. Install GNU coreutils: `brew install coreutils` provides `gtimeout`, which envup auto-detects.

## Configuration Sync

Configs are **symlinks**, not copies. Editing `~/.zshrc` actually edits `modules/zsh/files/.zshrc` in this repo.

```bash
# Make a change on machine A
vim ~/.zshrc                    # edits the repo file
git add . && git commit -m "..."
git push

# Pull on machine B
git pull                        # changes apply instantly (no reinstall)
source ~/.zshrc
```

For machine-specific settings that should NOT be synced, use the local-overrides file:

```bash
cp modules/zsh/files/.zshrc.d/local.zsh.example ~/.zshrc.d/local.zsh
# Edit freely — gitignored, won't sync
```

## Supported Platforms

| Platform | Tested |
|----------|--------|
| macOS (Apple Silicon / Intel) | ✓ |
| Ubuntu / Debian | ✓ |
| Fedora / CentOS | ✓ (best-effort) |
| Arch Linux | ✓ (best-effort) |
| Alpine | best-effort |
| WSL2 | ✓ |
| Docker | ✓ |

## Architecture & Contributing

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — design, guarantees, platform detection, mirrors
- [docs/TMUX.md](docs/TMUX.md) — tmux cheatsheet
- [CONTRIBUTING.md](CONTRIBUTING.md) — adding modules / profiles, tests, releasing
- [CHANGELOG.md](CHANGELOG.md) · [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) · [SECURITY.md](SECURITY.md)

## License

MIT — see [LICENSE](LICENSE)
