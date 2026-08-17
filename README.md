# envup

> One repo, one CLI, one command — cross-platform development environment.

[![CI](https://github.com/gendu-amd/envup/actions/workflows/ci.yml/badge.svg)](https://github.com/gendu-amd/envup/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
![Platforms](https://img.shields.io/badge/platform-macOS%20%7C%20Linux%20%7C%20WSL2%20%7C%20Docker-blue)
![Shell](https://img.shields.io/badge/shell-bash%20%E2%89%A5%204-green)

**English** | [简体中文](README.zh-CN.md)

A modular dotfiles manager that lets you set up your shell, editor, and CLI tools on any new machine with a single command. Pick a profile (minimal / standard / full) or install individual modules; uninstall anything you don't want; everything is logged and reversible.

It is built for the machines you don't control: **no root**, a **corporate proxy**, a **home directory shared across a cluster**, macOS and Linux side by side. On any of them the answer is either "installed" or a specific reason why not — never a hang and never a half-configured shell.

## Requirements

- **bash ≥ 4.0** (associative arrays for module dependency resolution). On **macOS**, `/bin/bash` is still 3.2 — run `brew install bash` once; `envup` auto-detects Homebrew's bash when you `./envup` (your login shell / tmux shell can stay zsh).
- **git ≥ 2.0** (submodule rename support; almost certainly already installed)
- **A POSIX system**: macOS, Linux (Ubuntu/Debian/Fedora/CentOS/Arch/Alpine), WSL2, or Docker

Everything below is **optional**:

- **root / sudo** — without it envup skips the system package manager and installs
  static binaries into `~/.local/bin` instead. Tools that need a compiler (`zsh`,
  `git`, `tmux`) come back **degraded**: their config is linked and starts working
  the moment an admin installs the package. Nothing prompts, nothing blocks.
- **A package manager** (apt / dnf / yum / pacman / brew / apk) — used when it is
  there and usable.
- **Network access** — a first install without it lands every config file and
  skips the downloads (`ENVUP_OFFLINE=1` to declare it up front).
- **Recommended**: `~/.local/bin` on `$PATH` so `envup` and anything it installs
  are reachable. The `zsh` module puts it there; `envup doctor` tells you if it
  isn't.

## Quick Start

```bash
# Clone (with submodules — required for zsh themes/tmux plugins)
git clone --recursive https://github.com/gendu-amd/envup.git
cd envup

# Forgot --recursive? Catch up:
#   git submodule update --init --recursive

# Install the standard profile (zsh, git, tmux, fzf, ripgrep, fd, bat, eza,
# zoxide, atuin, delta, direnv)
./envup install

# ... or pick a smaller profile
./envup install --profile minimal

# ... or install just what you need
./envup install zsh git

# Start a new shell
exec zsh
```

## What it looks like

A server where you have an account and nothing else:

```console
$ ./envup install --profile standard
[i] install order: zsh git tmux fzf ripgrep fd bat eza zoxide atuin delta direnv
==> [zsh] install
✓ linked: ~/.zshrc
...
==> [zoxide] install
[i] [zoxide] release v0.9.6: zoxide-x86_64-unknown-linux-musl.tar.gz
✓ [zoxide] zoxide v0.9.6 installed to ~/.local/bin

✓ ok:       zsh git fzf ripgrep fd bat eza zoxide atuin delta direnv
⚠ degraded: tmux (usable but incomplete — see above)

$ ./envup status
[i] Platform: linux (x86_64)  PkgMgr: apt  Priv: none
Modules:
  ✓ zsh      Modern shell with Oh-My-Zsh + Powerlevel10k theme
  ✓ git      Git config (~/.gitconfig with delta as pager)
  ~ tmux     Terminal multiplexer with TPM + session restore  — tmux not found
  ○ nvim     Neovim editor with NvChad config + lazy.nvim plugins
  ✓ ok   ~ degraded (config linked, tool missing)   ! broken   ○ not installed

$ ./envup doctor
==> environment
[i] os=linux distro=ubuntu-24.04 arch=x86_64 libc=glibc-2.39 priv=none pkg=apt net=direct
==> modules
✓ [zsh] ok (5.9)
⚠ [tmux] degraded: tmux not found
  → the config is linked — it starts working the moment the tool exists
✓ doctor: this machine is healthy (1 note(s) above)

$ ./envup status --json | jq '.modules[] | select(.state != "absent") | {name, state, provider}'
{ "name": "zoxide", "state": "ok", "provider": "github_release" }
```

> Prefer a recorded terminal cast? Generate one locally with
> [asciinema](https://asciinema.org): `asciinema rec` while you run the commands
> above, then link the resulting cast here.

## Commands

```bash
./envup install [--profile NAME] [--dry-run] [MODULE...]                     # Install
./envup uninstall [--all] [--dry-run] MODULE...                              # Remove
./envup upgrade [--profile NAME] [--ref TAG] [--dry-run] [--keep-going] ...  # update + reinstall
./envup status [--json]                                                      # Real state of each module
./envup doctor [--fix] [--authoring] [--module NAME]                         # Health-check this machine
./envup adopt [--dry-run] [PATH...]                                          # Move third-party edits out of the repo
./envup clean [--dry-run] [--all | MODULE...]                                # Clear caches (meta CLEAN_PATHS)
./envup log [--tail]                                                         # Most recent command's log
./envup --version                                                            # Print the envup version
```

Use `./envup <command> --help` for command-specific options.

A few important semantics that aren't obvious from the one-liners:

- **Install has four outcomes, not two.** `ok` (installed and verified), `degraded` (config linked, the tool itself couldn't be installed here), `skipped` (not applicable to this machine), `failed` (actually broke). Only `failed` is a non-zero exit — a degraded module on a locked-down server is the designed outcome, and scripts shouldn't treat it as an error. **One module's failure never aborts the rest of the run.**
- `install --profile X MODULE...` is a **UNION**, not OR — `envup install --profile minimal nvim` installs minimal's modules **and** nvim, deduped.
- `upgrade` by default only reinstalls modules **already in your manifest** (`~/.local/state/envup/installed`). If your team added a new module to a profile, pass `--profile NAME` to pick it up.
- `upgrade --ref v0.2.0` checks out a specific tag/branch (fetch + checkout + submodules) instead of pulling the current branch — use it to pin or roll to a released version.
- `status` reports what is **actually true on disk right now** — it re-reads every symlink and re-runs every version check. `✓ ok` / `~ degraded` / `! broken` / `○ not installed`. Delete a config by hand and status says `!` on the next run.
- `status --json` prints the same thing machine-readably (`state`, `tool`, `provider`, `version`, `broken_links` per module, plus platform / package manager / privilege level).
- `doctor` health-checks **this machine**: every managed symlink, every tool version, the manifest, submodules, `~/.local/bin` on `PATH`, locale validity, and whether the repo has been moved. `--fix` repairs what can be repaired and then **re-checks**, so a clean exit means "it is fixed", not "I tried".
- `doctor --authoring` is the other half: static validation of the modules in the repo (meta fields, function-wrapped hooks, valid `DEPENDS`, no hand-rolled downloads, `CLEAN_PATHS` that never targets user data). Run it after adding a module.
- `adopt` handles the case where a third-party installer appended itself to one of your tracked config files. It moves those lines to `~/.zshrc.local` and restores the repo file. See [Configuration Sync](#configuration-sync).
- **No step can hang the whole run:** network calls and the package manager are wrapped in timeouts, and each module hook runs under an outer watchdog (`ENVUP_MODULE_TIMEOUT`, default 900s). A stuck module is killed and reported failed; install continues with the rest. (Needs a `timeout`/`gtimeout` binary — on macOS: `brew install coreutils`.)
- **When `upgrade` can't move the source, it says which of envup's own failure modes it hit** — a managed config edited through its symlink (named file by file, with `envup adopt`), other uncommitted changes (with `git stash`), a HEAD left detached by an earlier `--ref` (caught before the fetch, with the way back), a branch with no upstream, or a directory that isn't a git checkout. Plugin submodules sitting at a newer commit are expected state and are not reported as dirt.
- `upgrade --keep-going` lets the run continue even if `git pull` failed; otherwise upgrade aborts to avoid silently reinstalling stale config.
- `upgrade --dry-run` skips `git pull` entirely and forwards `--dry-run` to install.
- `clean` removes module-managed plugin caches (lazy.nvim, mason, oh-my-zsh, etc.) — NOT the binary, NOT your config. Useful when nvim Lazy state gets weird.
- `log` shows the **most recent** command's log (install, uninstall, upgrade, or clean — whichever ran last).

## Machines you don't control

### No root

There is no `sudo` prompt anywhere in envup. It probes with `sudo -n true` — if that
doesn't pass without a password, the system package manager is simply off the table
and the run continues down the other routes. (The probe matters: a `sudo` that sits
waiting on a password in a non-interactive session is how installs used to hang for
fifteen minutes before the watchdog killed them.)

Each module declares an ordered fallback chain, and the engine picks the first one
that can work here:

| Provider | What it does | Needs root? |
|---|---|---|
| `system` | apt / dnf / yum / pacman / brew / apk | yes (except brew) |
| `github_release` | download the matching prebuilt binary → `~/.local/bin` | no |
| `git` | clone a repo that carries its own installer (fzf) | no |
| `script` | the vendor's official `curl \| sh` installer | no |
| `manual` | print instructions, mark the module `degraded` | — |

`github_release` matches assets against the detected OS / arch / libc — including
picking a **musl** build on a host whose glibc is too old — and pins versions in
`versions.lock` so every machine gets the same binary.

`zsh`, `git` and `tmux` need a compiler and have no static release to fetch. Without
root and without the package, they end up `degraded`: **the config files are still
linked**, and the tools start working the moment an admin installs the package. No
reinstall needed.

### Proxy, mirror, or no network at all

```bash
ENVUP_GH_MIRROR=https://ghproxy.com ./envup install    # route GitHub through a mirror
ENVUP_OFFLINE=1 ./envup install --profile minimal      # don't even try; land the configs
ENVUP_REQUIRE_CHECKSUM=1 ./envup install               # refuse what can't be checked
```

A downloaded release binary is checked against the digest published in the same
release (`checksums.txt`, `<asset>.sha256`, and the other spellings upstreams use).
That does not protect you from a compromised upstream — the digest travels the same
link as the file — but it does catch the failures that actually happen: a proxy
answering 200 with a login page, a transfer cut off mid-file, a mirror a week behind
still serving the previous release. All three install cleanly today and go wrong
somewhere else later.

Plenty of upstreams (fd, bat, delta) publish no digest at all, so "nothing to check
against" is a debug log line and the install continues. `ENVUP_REQUIRE_CHECKSUM=1`
makes it a refusal instead — worth setting when `ENVUP_GH_MIRROR` points at a proxy
you don't run.

Every outbound request in envup goes through one place (`lib/net.sh`), so those
variables cover all of it — releases, clones, and vendor install scripts alike. A
module that reaches for `curl` on its own is a lint error, precisely so this stays
true. `envup doctor --authoring` enforces it.

`https_proxy` / `http_proxy` are preserved across privilege escalation (envup uses
`sudo -E` when a proxy is set), which is what makes `apt-get install` work behind a
corporate proxy at all.

For the git **submodules** (zsh/tmux plugins), use git's own redirect:
`git config --global url."https://ghproxy.com/https://github.com/".insteadOf https://github.com/`.

### A home directory shared across machines

Common on clusters with NFS/autofs mounts. Two things follow from it, and envup
handles both:

- Symlink ownership is decided by comparing paths both resolved and unresolved, so a
  `/home` → `/mnt/home` automount doesn't make envup refuse to remove its own links.
- Per-machine config goes in a `hosts/<hostname>` file (committed, syncs, stays
  separate per machine) rather than in one shared "local" file — for zsh, tmux,
  nvim and git alike. See [Configuration Sync](#configuration-sync).

## Profiles

| Profile | Modules | Use case |
|---------|---------|----------|
| `minimal` | `zsh git` | Bare server, headless container |
| `standard` (default) | `+ tmux fzf ripgrep fd bat eza zoxide atuin delta direnv` | Typical developer workstation |
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
MODULES+=(tmux fzf ripgrep fd bat eza zoxide atuin delta direnv)

# profiles/full.sh = standard + editor
use_profile standard
MODULES+=(nvim)
```

Want a bigger set? Either `use_profile` an existing one and append, or union on
the CLI: `./envup install --profile standard nvim`.

## Modules

Each module is a self-contained directory under [`modules/`](modules/):

```
modules/<name>/
├── meta.sh          # Pure data: what to install, how to verify, what to link
├── hooks.sh         # Optional: pre/post_install, pre/post_uninstall functions
└── files/           # Config files (symlinked to ~/)
```

`meta.sh` **declares**, it doesn't execute — the engine reads it and drives the
install. A whole module can be a dozen lines with no logic at all:

```bash
NAME="zoxide"
DESCRIPTION="Smarter cd — 'z <dir>' to jump, 'zi' to pick interactively"
DEPENDS=(zsh)

VERIFY_BIN="zoxide"                                   # how the engine knows it worked
PROVIDERS=(system github_release script)              # ordered fallback chain
GH_REPO="ajeetdsouza/zoxide"
SCRIPT_URL="https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh"

LINKS=()                                              # "<repo path>:<target>" pairs
CLEAN_PATHS=()
```

Adding a new tool = creating a new directory. No registry, no config update. See
[CONTRIBUTING.md](CONTRIBUTING.md) for the full contract.

| Module | Tool | Depends |
|--------|------|---------|
| `zsh` | Modern shell with Oh-My-Zsh + Powerlevel10k (also makes zsh your default shell) | — |
| `git` | Git config (delta as pager where delta is installed) | — |
| `delta` | Syntax-highlighted git diffs, wired in as git's pager | `git` |
| `tmux` | Terminal multiplexer (new panes use zsh, `prefix f` project switcher, OSC 52 clipboard, session restored after a reboot) | — |
| `fzf` | Fuzzy finder (Ctrl+T / Ctrl+R) | — |
| `ripgrep` | Fast recursive search (`rg`); also what Telescope greps with | — |
| `fd` | Friendlier `find`; also what fzf lists files with | — |
| `bat` | `cat` with syntax highlighting; what `cat` and fzf's preview use | — |
| `eza` | A modern `ls` — what `ls`/`ll`/`la`/`tree` become | — |
| `direnv` | Per-directory environment, loaded on `cd` from `.envrc` | `zsh` |
| `zoxide` | Smarter `cd` — `z <dir>` to jump, `zi` to pick | `zsh` |
| `atuin` | SQLite-backed shell history | `zsh` |
| `nvim` | Neovim with NvChad (plugins pinned via lazy-lock.json) | — |

### Working on a remote box

Three things the tmux module adds that only matter over SSH:

**A reboot does not cost you your session.** The layout you were working in —
windows, panes, directories, scrollback, the files open in nvim — is saved every
five minutes, and logging back in puts you straight back into it. Nothing to
type: the login shell starts the tmux server, waits for the restore, and attaches.
Saves are kept per machine, so a home directory shared over NFS does not hand you
the build box's layout on the GPU box. `NO_TMUX=1 ssh box` for a connection where
you want a plain shell. See [docs/TMUX.md](docs/TMUX.md).

**Copy lands on your laptop.** Yank in nvim or copy in tmux and the text goes to the
clipboard of the machine you are sitting at, carried by the SSH connection you
already have — no X11 forwarding, no root, no daemon. It needs one setting in your
*local* terminal, which envup cannot set for you: see
[docs/CLIPBOARD.md](docs/CLIPBOARD.md). (VS Code and Cursor ship it turned off.)

**`prefix f` switches projects.** fzf over your project roots, then attach-or-create
a tmux session named after the project — so picking one you already have open takes
you back to it instead of opening a second copy. In a popup over the current pane
where tmux is 3.2 or newer, in a throwaway window where it is older; the binding
asks. Also `ts` from the shell. Roots are
`~/work/*`, `~/src/*`, `~/projects/*`, `~/dev/*`, `~/repos/*`, `~/go/src/*/*` unless
you list your own in `~/.config/envup/project-dirs`. See
[docs/TMUX.md](docs/TMUX.md).

### Default shell

The `zsh` module makes zsh the shell you actually land in, on three fronts:

1. `chsh` changes your login shell (effective next login).
2. On accounts where `chsh` is blocked (LDAP/SSSD-managed corp/HPC boxes), a
   small guarded block is added to `~/.bashrc` that `exec`s zsh for interactive
   bash. Escape hatch: `NO_ZSH=1 bash`.
3. The `tmux` module sets `default-command zsh`, so new panes use zsh
   regardless of the system login shell.

`envup uninstall zsh` removes the `~/.bashrc` block (it leaves the `chsh`
setting alone). If envup created `~/.bashrc` in the first place — a home that
never had one — and the block was the only thing in it, the file goes too. A
`~/.bashrc` that was already there, or that you have since written to, stays.

### nvim module

The `nvim` module symlinks the NvChad config to `~/.config/nvim` and installs
plugins. NvChad needs **nvim >= 0.10**, and the distro package is often older —
Debian stable and RHEL both are. envup handles that itself: the engine sees the
version shortfall, keeps walking the provider chain, and installs the official
release build into `~/.local/bin` instead. envup never touches your system
package sources.

If even that isn't possible (no network, unusual architecture), the module
degrades and prints your options:

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

**Editing over SSH.** Three defaults chosen for the way a server actually gets
used, all of them adjustable:

- Undo survives the session (`undofile`). A dropped connection kills the shell
  and nvim with it; without this, everything since the last write goes too.
- Past 1.5 MB a buffer opens with syntax, treesitter, LSP, folding, undo and
  swap switched off, and tells you it did. Tailing a 200 MB log stops being a
  killed terminal. `vim.g.envup_bigfile_bytes = 0` disables it.
- Format on save runs **only where the project ships its own style config**
  (`.clang-format`, `stylua.toml`, `pyproject.toml`, …), because clang-format
  with no `.clang-format` reflows the whole file to LLVM style — and in someone
  else's repository, that diff is yours to explain. `<leader>fm` formats on
  demand regardless; `vim.g.envup_format_always = true` makes it unconditional.

## How It Works

```
┌───────────────────────────────────────────────────────────────┐
│  ./envup install --profile standard                           │
│         ↓                                                     │
│  detect capabilities: OS, distro, arch, libc, privilege, net  │
│         ↓                                                     │
│  load profiles/standard.sh → MODULES=(zsh git ...)            │
│         ↓                                                     │
│  resolve order (each module's DEPENDS first)                  │
│         ↓                                                     │
│  for each module, the engine:                                 │
│    reads meta.sh (data only)                                  │
│    walks PROVIDERS until one works, given the capabilities    │
│    symlinks LINKS into ~/ (backing up anything real)          │
│    runs hooks.sh post_install, if present                     │
│    verifies VERIFY_BIN / VERIFY_MIN_VERSION                   │
│    records name + state + provider + version in the manifest  │
│         ↓                                                     │
│  ok / degraded / skipped / failed, per module, with reasons   │
│         ↓                                                     │
│  log to ~/.local/state/envup/logs/install_<ts>.log            │
└───────────────────────────────────────────────────────────────┘
```

Key properties:

- **Idempotent**: Re-running `./envup install` is safe. Existing symlinks are detected and skipped.
- **Reversible**: Every overwritten file is backed up to `~/.dotfiles_backup/<timestamp>/`. `./envup uninstall` removes only envup-managed symlinks — plus the two things it created that aren't symlinks: a directory that exists only to hold one (removed only while empty), and a `~/.bashrc` that envup itself had to create for the zsh shim (removed only if envup created it *and* it is empty again). Your files, your packages and your `~/.gitconfig.local` are never touched.
- **Loggable**: Every command writes a timestamped log under `~/.local/state/envup/logs/`. Use `./envup log --tail` to follow live.
- **Cross-platform**: macOS, Linux (apt/dnf/yum/pacman/brew/apk), WSL2, Docker. Auto-detects the platform and package manager.
- **Degradable**: what can't be installed here is reported, not fatal — and the config lands either way.

## Environment Variables

envup recognises these env vars at install time. All are optional; defaults are sensible for the common case.

| Variable | Default | Effect |
|---|---|---|
| `ENVUP_DRY_RUN` | `0` | When `1`, every destructive step prints what it would do without changing anything. `--dry-run` sets this automatically. |
| `ENVUP_OFFLINE` | `0` | When `1`, no network is attempted at all — downloads decline immediately instead of waiting for a timeout, and configs are still linked. |
| `ENVUP_GH_MIRROR` | — | Prefix that all GitHub traffic is routed through, e.g. `https://ghproxy.com`. Covers releases, clones and vendor install scripts. |
| `ENVUP_REQUIRE_CHECKSUM` | `0` | When `1`, a release binary that can't be checked against a published digest is refused instead of installed. Off by default because several upstreams (fd, bat, delta) publish no checksums at all. Worth turning on with `ENVUP_GH_MIRROR`. |
| `ENVUP_LOCAL_BIN` | `~/.local/bin` | Where root-free installs put binaries. |
| `ENVUP_LOG_LEVEL` | `info` | `debug`/`info`/`warn`/`error` — terminal verbosity. The log file always records everything. |
| `ENVUP_MODULE_TIMEOUT` | `900` | Outer watchdog around each module hook. A hung module is killed and reported failed; the run continues. |
| `ENVUP_NVIM_LAZY` | `restore` | `restore` installs the pinned versions from `lazy-lock.json`; `sync` updates to latest and rewrites the lock; `skip` leaves them for nvim's first launch. |
| `ENVUP_ATUIN_INSTALL` | — | Set to `skip` to skip the atuin module (handy when its installer is blocked by a network/proxy). |
| `ENVUP_ZSH_QUIET` | `0` | Shell-side: when `1`, a config slice that fails to load does so silently. Default is to print which slice broke and why. |
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

**Start with `envup doctor`.** It checks the machine, names what is wrong, and
`--fix` repairs most of it:

```bash
./envup doctor          # what's broken here?
./envup doctor --fix    # repair, then re-check and report the real verdict
```

If something still fails:
1. Check the log — every command's exit code, duration, and any stderr is captured.
2. Re-run with `--dry-run` to see what would happen without doing anything.
3. `ENVUP_LOG_LEVEL=debug` shows the provider decisions (why this route and not that one).
4. The module is at `modules/<name>/` — `meta.sh` is data, `hooks.sh` is the custom steps.

### Common issues

**Modules come back `degraded`** — that's a report, not a failure: the config is
linked but the tool itself couldn't be installed here (usually no root and no static
release to fall back on). `envup doctor` names the tool. Once someone installs the
package it works with no reinstall.

**zsh prompt is plain / Powerlevel10k missing** — you probably forgot `--recursive` when cloning. `envup doctor` reports this explicitly; fix:
```bash
git submodule update --init --recursive   # or: ./envup doctor --fix
./envup install zsh
```

**`setlocale: cannot change locale`** — envup 0.2 no longer forces a locale: it picks the first of `en_US.UTF-8` / `C.UTF-8` that the machine actually has, sets only `LANG`, and never sets `LC_ALL`. If you still see the warning, something else in your environment is setting it — `envup doctor` reports both cases.

**`envup: command not found` after install** — the `zsh` module symlinks `envup` to `~/.local/bin/envup`. Make sure `~/.local/bin` is on `$PATH` (login again, or `exec zsh`). `envup doctor` flags it if it isn't.

**Everything broke after moving the repo** — every symlink points at the old path. envup records where links were made from, so this is one message rather than twenty: `envup doctor --fix` relinks from the new location.

**`envup upgrade` won't update the source** — it now tells you which of these it
is instead of leaving you with git's message alone. A tracked config file was
edited in place (something appended through the `~/.zshrc` symlink) → the files
are listed and `envup adopt` moves the additions out; see
[Configuration Sync](#configuration-sync). Other uncommitted changes → listed,
with `git stash`. HEAD detached, which is what an earlier `upgrade --ref v0.2.0`
leaves behind → caught before the fetch, with `envup upgrade --ref main` as the
way back. A branch with no upstream, or a checkout that isn't a git repo at all
→ named as such.

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

### Per-machine settings

There are two layers, and the difference is whether you want the setting to survive
the machine being rebuilt:

```bash
# Committed, syncs everywhere, keyed by hostname — proxies, CUDA prefixes,
# `module load` lines, the timezone, machine-specific aliases.
cp ~/.zshrc.d/hosts/example.zsh.template ~/.zshrc.d/hosts/$(hostname -s).zsh

# Never committed, lives outside the repo, loads last so it wins — tokens,
# one-off experiments.
$EDITOR ~/.zshrc.local              # this home directory
$EDITOR ~/.zshrc.local.$(hostname -s)   # this machine only
```

The private layer deliberately lives in `$HOME`, **not** inside the repo checkout. A
gitignored file inside the checkout is a trap: it can't sync, on a shared NFS home
every machine gets the same one, and anything writing to `~/.zshrc` is writing into
version control.

The same two layers exist for tmux, nvim and git, each with a template to copy:

| Module | Committed, per machine | Private, wins |
|---|---|---|
| zsh | `modules/zsh/files/.zshrc.d/hosts/<host>.zsh` | `~/.zshrc.local` |
| tmux | `modules/tmux/files/hosts/<host>.conf` | `~/.tmux.local` |
| nvim | `modules/nvim/files/hosts/<host>.lua` | `~/.config/nvim/local.lua` |
| git | `modules/git/files/hosts/<host>.gitconfig` | `~/.gitconfig.local` |

```bash
cp modules/tmux/files/hosts/example.conf.template \
   modules/tmux/files/hosts/$(hostname -s).conf
envup install tmux          # links it into place
```

Neither tmux's `source-file` nor git's `[include]` can expand a hostname, so envup
resolves it at install time and links your file to one fixed path
(`~/.tmux/host.conf`, `~/.gitconfig.host`). That is why a **new** host file needs one
`envup install <module>`; editing an existing one does not. zsh and nvim read the
hostname themselves and need neither.

git has a third layer below both: `~/.gitconfig.envup`, rewritten on every install
from what envup can actually find on this machine — the delta pager is enabled there
if delta exists, and nowhere at all if it doesn't. The committed `.gitconfig` names
no binary, so `git diff` cannot break on a machine that is missing one.

### When something writes into your repo anyway

Because `~/.zshrc` is a symlink into the checkout, a third-party installer that
"helpfully" appends to it is appending to a tracked file — and the next
`envup upgrade` fails its `git pull` on a different machine.

`envup doctor` spots this, and `envup adopt` undoes it:

```console
$ envup doctor
⚠ modules/zsh/files/.zshrc has lines appended after the last commit — a tool may have edited it
  → move them out of the repo: envup adopt modules/zsh/files/.zshrc

$ envup adopt
✓ modules/zsh/files/.zshrc: appended lines moved to ~/.zshrc.local, file restored
[i] adopted 1 file(s)
```

It only touches changes that are a **pure append** to a committed file. Anything you
edited yourself is reported and left alone.

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
- [docs/TMUX.md](docs/TMUX.md) — tmux cheatsheet, the project sessionizer, per-machine config
- [docs/CLIPBOARD.md](docs/CLIPBOARD.md) — copying from a server to your laptop over OSC 52
- [CONTRIBUTING.md](CONTRIBUTING.md) — adding modules / profiles, tests, releasing
- [CHANGELOG.md](CHANGELOG.md) · [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) · [SECURITY.md](SECURITY.md)

## License

MIT — see [LICENSE](LICENSE)
