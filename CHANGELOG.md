# Changelog

All notable changes to envup are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2026-08-15

A cross-platform correctness release. 0.1.0 got the engineering shell right
(tests, CI, versioning) but never touched runtime behaviour on the machines that
matter: servers without root, restricted networks, home directories shared over
NFS, macOS and Linux side by side. This release rebuilds the module contract and
the shell config model around those.

**This release contains breaking changes.** See *Migrating from 0.1.x* below.

### Machines without root

- **Module contract v2.** `meta.sh` is now pure declarative data; the install is
  driven by an engine (`lib/engine.sh`) with five pluggable providers
  (`system`, `github_release`, `git`, `script`, `manual`). Modules declare an
  ordered fallback chain and the engine picks the first route that works here.
- **`github_release` provider** downloads prebuilt binaries into `~/.local/bin`,
  matching assets against the detected OS / arch / libc — including choosing a
  musl build when the host's glibc is too old — and pinning versions in
  `versions.lock`. This is what makes a no-sudo server usable.
- **Four install outcomes** — `ok` / `degraded` / `skipped` / `failed` — with a
  per-module reason. A tool that can't be installed here still gets its config
  linked (`degraded`) and starts working the moment the package appears. Only
  `failed` is a non-zero exit.
- **One module's failure no longer aborts the run.** Missing prerequisites are
  advisory; previously any `SELF_DEPS` failure stopped every profile dead on a
  machine without root.
- **Privilege detection via `sudo -n true`.** A `sudo` that exists but wants a
  password is treated as no privilege at all, instead of blocking a
  non-interactive install until the 900s watchdog killed it.
- Cross-distro package names (`PKG_NAMES`), so `fd`→`fd-find` and friends are
  expressible.

### Restricted networks

- **All network egress goes through `lib/net.sh`.** `ENVUP_GH_MIRROR` and the new
  `ENVUP_OFFLINE=1` now cover releases, clones and vendor install scripts alike —
  including atuin's installer, which previously bypassed the mirror entirely.
  `doctor --authoring` rejects a module that calls `curl`/`wget`/`git clone`
  directly.
- **Proxy variables survive privilege escalation** (`sudo -E` when a proxy is
  set); `sudo`'s `env_reset` used to strip them and break `apt-get` on every
  corporate network.
- A failed `apt-get update` is no longer recorded as a success.

### Shell behaviour

- **Config slices are numbered and reordered.** `20-platform` now runs *before*
  `50-tools`, fixing the bug where every Homebrew-installed tool (zoxide, atuin,
  fzf) silently failed to initialise on macOS because `brew shellenv` hadn't run
  yet.
- **Nothing is set unconditionally any more.** `LANG` is only set to a locale the
  machine actually has and `LC_ALL` is never set; `TZ` is left alone; `EDITOR` is
  the first of `nvim`/`vim`/`vi` that exists; `alias vim=nvim` is only created if
  nvim is installed. The old behaviour broke `git commit`, `crontab -e` and every
  command's output on minimal servers.
- **PATH is built with idempotent helpers** and never reorders the inherited
  value. `.zshenv` used to prepend the system directories ahead of everything
  inherited, demoting brew / conda / HPC `module load` toolchains, and PATH grew
  without bound in nested shells.
- `compinit` runs exactly once (was twice, costing 100–300ms — worse on NFS);
  nvm is a lazy shim (was 200–800ms at startup); the WSL2 slice no longer calls
  `cmd.exe` synchronously on startup; macOS no longer overrides the eza aliases.
- **Slice errors are no longer swallowed.** A slice that fails prints which one
  and why; `ENVUP_ZSH_QUIET=1` restores the old silence.

### Multi-machine

- **New `hosts/` layer**: `~/.zshrc.d/hosts/<short-hostname>.zsh` is committed,
  so per-machine settings sync and survive a rebuild — and stay separate on a
  shared home. Private overrides moved to `~/.zshrc.local` (and
  `~/.zshrc.local.<hostname>`), **outside** the repo checkout.
- **Symlink ownership is compared both resolved and unresolved**, so a home
  automounted as `/home` → `/mnt/home` no longer makes `uninstall` refuse to
  remove envup's own links.
- **`_realpath`** falls back `readlink -f` → python3 → `cd -P && pwd -P`, correct
  on macOS without coreutils. Previously the "already linked" check was always
  false there, relinking on every run.
- **Manifest schema 2** records state, provider, version, timestamp and the repo
  root. Moving the checkout is now reported as one message instead of twenty
  dangling links, and `doctor --fix` relinks from the new location.
- **New `envup adopt`**: when a third-party installer appends itself to a tracked
  config file (reachable because `~/.zshrc` is a symlink into the repo), move
  those lines to `~/.zshrc.local` and restore the file — instead of a failing
  `git pull` on the next machine.

### Diagnosability

- **`envup doctor` now health-checks the machine** — every managed symlink, tool
  version, manifest entry, submodule, `~/.local/bin` on PATH, locale validity,
  repo drift and relocation. `--fix` repairs and then **re-checks**, so a clean
  exit means "it is fixed", not "I tried". The old module-authoring validation
  moved to `doctor --authoring`.
- Findings are split into **issues** (broken, exit 1, fixable) and **notes**
  (working as designed, exit 0) — a degraded module on a locked-down server no
  longer fails the check.
- **`envup status` reports what is true on disk**, re-reading every symlink and
  re-running every version check: `✓ ok` / `~ degraded` / `! broken` /
  `○ not installed`. It could previously show `✓` for a config you had deleted.
  `--json` gained `state`, `tool`, `provider`, `version`, `broken_links`, `priv`
  and `net`.
- `clean --all` no longer depends on argument order.

### Internals

- `lib.sh` split into `lib/` (`log` `caps` `fs` `net` `pkg` `manifest` `module`
  `engine` `providers/*` `health` `adopt` `authoring` `doctor`); `envup` is a
  dispatcher.
- The module watchdog re-execs `"$BASH"` rather than a bare `bash`, so macOS
  hooks keep bash ≥ 4 instead of falling back to 3.2.
- `--dry-run` is total again: `install --dry-run` on a machine without nvim no
  longer fails with a misleading `nvim too old:`.
- Test suite grew to 200+ unit tests plus integration; CI gained an unprivileged
  container job and an offline job, and installs `zsh` so the shell-config tests
  actually run.

### Migrating from 0.1.x

Breaking, in rough order of how likely you are to notice:

1. **Personal overrides moved.** `~/.zshrc.d/local.zsh` (inside the checkout,
   gitignored) is replaced by `~/.zshrc.local`. The old file is still sourced
   with a warning, so nothing is lost — move it when convenient:
   `mv ~/.zshrc.d/local.zsh ~/.zshrc.local`.
2. **Machine-specific config has a real home.** Anything in your old `local.zsh`
   that other machines should also get belongs in
   `~/.zshrc.d/hosts/$(hostname -s).zsh` (committed). Start from
   `~/.zshrc.d/hosts/example.zsh.template`.
3. **`bare envup doctor` changed meaning** — it health-checks the machine now.
   If you called it in CI to validate modules, use `envup doctor --authoring`.
4. **`LC_ALL`, `TZ` and `EDITOR` are no longer forced.** If you relied on envup
   exporting `LC_ALL=en_US.UTF-8` or `TZ=UTC`, set them yourself in the host or
   local layer.
5. **Custom modules must be ported** to the v2 contract: move `install.sh` /
   `uninstall.sh` logic into `hooks.sh` functions and describe the install in
   `meta.sh`. `envup doctor --authoring` names every leftover.
6. The manifest upgrades itself on the next install; schema 1 files still read.

There is no compatibility switch for any of the above — envup is small enough,
and used by few enough people, that carrying two code paths costs more than the
one-time move.

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
