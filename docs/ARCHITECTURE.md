# envup architecture

envup keeps your shell/editor/terminal setup consistent across machines —
including the ones where you have an account and nothing else.

```
envup                  # CLI: one cmd_* function per command + dispatch. A dispatcher.
lib.sh                 # thin loader: sources lib/*.sh in dependency order
lib/
  log.sh               # logging + log levels + where per-machine state lives
  caps.sh              # capability detection: OS/distro/arch/libc/privilege/network
  fs.sh                # _realpath, safe_link, unlink_safe, block_set/del,
                       # and the two reclaim paths: empty dirs, files envup made
  net.sh               # gh_url, net_run, net_fetch, net_clone, offline handling,
                       # and release-checksum verification of what came back
  pkg.sh               # package-manager abstraction + cross-distro package names
  manifest.sh          # the manifest (schema 2: state/provider/version/time + repo root)
  module.sh            # meta reading, dependency resolution, profiles
  verify.sh            # is a tool present, runnable and new enough — asked by
                       # engine, health, doctor and hooks, so it installs nothing
  engine.sh            # the install engine: providers → links → hooks → verify
  providers/
    system.sh          # apt/dnf/yum/pacman/brew/apk
    github_release.sh  # prebuilt binaries → ~/.local/bin      ← the no-root workhorse
    git.sh             # clone a repo that carries its own installer
    script.sh          # the vendor's official curl|sh installer
    manual.sh          # print instructions, mark the module degraded
  health.sh            # read-only inspection: what is actually true on disk
  adopt.sh             # move third-party appends out of the tracked repo
  upgrade.sh           # move the checkout forward, and say why it wouldn't
  authoring.sh         # static validation of module conventions
  doctor.sh            # the machine health check
modules/<name>/
  meta.sh              # module contract v2 — pure data
  hooks.sh             # optional: pre/post_install, pre/post_uninstall functions
  files/               # configs that get symlinked into $HOME
profiles/<name>.sh     # MODULES=(...) — a named set, composable via use_profile
```

The load order in `lib.sh` is the dependency order, and it is also the shape of the
program: detect what this machine can do → act on it → report on what happened.

## The module contract (v2)

`meta.sh` is **data**. It is sourced, never executed for effect, and every field is
read by `lib/engine.sh`:

| Field | Meaning |
|---|---|
| `NAME` / `DESCRIPTION` | identity; `DESCRIPTION` is what `envup status` prints |
| `DEPENDS=(...)` | other modules, installed first |
| `PROVIDERS=(...)` | **ordered fallback chain** — the first one that can work here wins |
| `GH_REPO` / `SCRIPT_URL` / `GIT_URL` / … | per-provider parameters |
| `PKG_NAMES=("apt:fd-find" "brew:fd")` | package name per packaging family; `-` means "no such package here" |
| `VERIFY_BIN` / `VERIFY_MIN_VERSION` / `VERIFY_VERSION_ARG` | the success criterion. Unverified is not installed. |
| `LINKS=("<repo path>:<target>")` | symlinks the engine creates; a leading `?` marks one as optional |
| `APPLIES_IF` | a condition; false means the module is `skipped`, not failed |
| `CLEAN_PATHS=(...)` | caches `envup clean` removes — never config, never user data |

`hooks.sh` is optional and holds **functions** (`post_install()` and friends). That
it is functions rather than a bare script is not a style preference: hooks are
sourced into a non-function subshell, where a top-level `local` is a syntax error.
Wrapping them removes the entire class of bug.

The engine drives everything else: pick a provider, install, link, run hooks, verify,
record. A module with no custom steps needs no code at all.

Verification asks the tool for its version and **reads the exit status**, not just
the output. A binary can be on `PATH`, be executable, and still be unusable — a
prebuilt release linked against a newer glibc than the host says ``version
`GLIBC_2.33' not found`` and dies. That message contains a dotted number, so an
output-only check reported nvim as `ok (2.33)` on a machine where nvim could not
start. A tool that exits non-zero has no version; it is `broken`, the engine keeps
walking the provider chain, and `doctor` raises an issue rather than a note. Tools
that answer on another flag set `VERIFY_VERSION_ARG` (tmux before 3.1 knows only
`-V`); anything stranger replaces the check with `verify()` in `hooks.sh`.

### Four outcomes

`ok` · `degraded` · `skipped` · `failed`. The distinction that matters is
**degraded vs failed**: a tool that can't be installed on this machine (no root, no
static release) still gets its config linked and starts working the moment someone
installs the package. Only `failed` is a non-zero exit, and no single module's
failure aborts the rest of the run.

## Capabilities

`lib/caps.sh` probes once and exports the result, so hooks in subshells reuse it:

`ENVUP_OS` · `ENVUP_DISTRO` / `_VER` / `_LIKE` · `ENVUP_ARCH` (normalised, so
`arm64` and `aarch64` don't produce two answers) · `ENVUP_LIBC` (`glibc-<ver>` or
`musl`, which decides whether a prebuilt binary will even run) · `ENVUP_PRIV` ·
`ENVUP_NET` · `ENVUP_HOST` · `ENVUP_HOME_SHARED`.

Two of these carry most of the weight:

- **`ENVUP_PRIV`** is `root` / `sudo` / `sudo-interactive` / `none`, and the probe is
  `sudo -n true`. A `sudo` that exists but wants a password is **not** `sudo` —
  treating it as such is how a non-interactive install used to block until the
  900-second watchdog killed it.
- **`ENVUP_NET`** is `direct` / `mirror` / `offline`, probed lazily via `caps_net()`.
  Lazily, because a read-only command like `status` must not spend five seconds
  reaching for GitHub to answer a local question. Never read the variable directly;
  call `caps_net`.

When a proxy is set, `priv_run` adds `sudo -E`. Without it `sudo`'s `env_reset`
strips `http_proxy`, and `apt-get install` fails on every corporate network.

## Networking

Every outbound request goes through `lib/net.sh` — releases, clones, vendor scripts.
That single choke point is what makes `ENVUP_GH_MIRROR` and `ENVUP_OFFLINE` work
everywhere at once, and what makes timeouts universal. It also means `gh_url` sees
URLs that have nothing to do with GitHub, so it rewrites only GitHub's own hosts —
prefixing a GitHub proxy onto a vendor's installer produces an address no proxy
can serve. `envup doctor --authoring`
rejects a module that reaches for `curl`/`wget`/`git clone` on its own, precisely so
the choke point stays a choke point.

## Key guarantees

- **Backup, never clobber.** `safe_link` moves any pre-existing *real* file at a link
  target into `~/.dotfiles_backup/<timestamp>/` before linking, keeping the path it
  had under `$HOME` (`~/.config/git/ignore` → `<backup>/.config/git/ignore`).
  Flattening to a basename made the guarantee conditional on no two link targets
  ever sharing a name: the second `mv` overwrote the first one's backup, silently.
  Mirroring the path also means the backup records where the file belongs, which
  is the other half of what a backup is for.
- **Idempotent.** Re-running install is a no-op for already-correct symlinks.
- **Reversible.** `unlink_safe` only removes symlinks that point inside the repo.
  Ownership is decided by comparing paths **both resolved and unresolved** — on a
  home directory automounted as `/home` → `/mnt/home`, a resolved-only comparison
  makes envup refuse to remove its own links.
  Not everything envup creates is a symlink, so two narrower reclaims sit beside
  it: `dir_prune_empty` gives back a directory that was only ever made to hold a
  link (`~/.config/git`, `~/.tmux/plugins`, an unused `~/.local/bin`), using
  `rmdir` so a non-empty one is impossible to take; and `created_note` /
  `created_reclaim` let `block_del` delete a `~/.bashrc` that envup itself had to
  create — recorded at creation time in `$ENVUP_STATE_DIR/created`, and only
  while it is still empty, because "delete any empty file" would break the same
  guarantee from the other side.
- **`_realpath`** falls back `readlink -f` → python3 → `cd -P && pwd -P`, so it is
  correct on a macOS without coreutils.
- **No step can wedge the whole run.** `net_run` wraps git/curl, `pkg_install` wraps
  the package manager, and `run_module_hook` puts an outer watchdog
  (`ENVUP_MODULE_TIMEOUT`, default 900s, SIGTERM then SIGKILL) around every hook.
  Return codes 70/71/79 carry state through that watchdog — deliberately clear of
  `timeout`'s own 124/137/143.
- **Dry-run is total.** `ENVUP_DRY_RUN=1` / `--dry-run` previews every change,
  including inside providers.

## Observability

`status` and `doctor` cannot disagree, because both read the same function:
`health_probe` in `lib/health.sh` re-reads every symlink and re-runs every version
check. The manifest records what envup *did*; health reports what is *true now*.

`doctor` splits its findings in two, and the split decides the exit code:

- an **issue** is something broken — a dangling link, an orphaned manifest entry.
  Exit 1, and `--fix` can usually repair it.
- a **note** is worth knowing but not wrong — a degraded module on a server without
  root is the designed outcome. Exit 0.

A tool that fails its exit code over things that are working as intended is a tool
people stop running.

`doctor --fix` runs a second, read-only pass afterwards and lets *that* decide the
verdict: "I tried to fix it" is a weaker claim than "it is fixed".

## The shell config model

`~/.zshrc` sources numbered slices from `~/.zshrc.d/`, and the numbers *are* the
design — the previous ordering bug (tools before platform) silently disabled every
Homebrew-installed tool on macOS.

| Slice | Responsibility |
|---|---|
| `00-guard` | p10k instant prompt, early guards |
| `10-path` | PATH built via idempotent `path_prepend`/`path_append`; inherited PATH never reordered |
| `20-platform` | OS detection + `platform/<os>.zsh` — **`brew shellenv`, ROCm/CUDA, WSL live here** |
| `30-env` | locale / TZ / EDITOR — all conditional on what exists |
| `40-shell` | Oh-My-Zsh, p10k, history, `compinit` (exactly once) |
| `50-tools` | fzf / zoxide / atuin / direnv — **after** platform, so brew's tools are findable |
| `55-node` | nvm as a lazy shim, not a 200–800ms startup cost |
| `60-alias` / `65-func` | aliases and functions, conditional on the binary existing |
| `70-host` | `hosts/<short-hostname>.zsh` — committed per-machine config |
| `80-local` | `~/.zshrc.local` — private, outside the checkout, loads last |

Three rules the slices follow:

- **Never set what you can't verify.** `LC_ALL` is never set (it overrides every
  `LC_*` category); `LANG` is set only to a locale `locale -a` actually lists;
  `EDITOR` is the first of `nvim`/`vim`/`vi` that exists; `alias vim=nvim` is only
  created if nvim is there. The old unconditional versions broke `git commit` and
  `crontab -e` on any minimal server.
- **Never reorder the inherited PATH.** Prepending the system directories demoted
  brew, conda and HPC `module load` toolchains.
- **Never swallow stderr.** A slice that fails prints which slice and why;
  `ENVUP_ZSH_QUIET=1` restores the silence for a machine that needs it.

The private layer lives in `$HOME`, not in the checkout: a gitignored file inside the
repo can't sync, is shared by every machine on an NFS home, and puts anything writing
to `~/.zshrc` inside version control. `envup adopt` cleans up after tools that did.

## The per-machine layer, generalised

The last two slices are not a zsh idea; they are the answer to "this box is
different". Every module whose config differs between machines has the same pair,
in the same order — repo default, then committed per-machine, then private.

| Module | Committed per-machine | Private | Resolved by |
|---|---|---|---|
| zsh | `.zshrc.d/hosts/<host>.zsh` | `~/.zshrc.local` | zsh, at startup |
| nvim | `hosts/<host>.lua` | `~/.config/nvim/local.lua` | lua, at startup |
| tmux | `hosts/<host>.conf` → `~/.tmux/host.conf` | `~/.tmux.local` | **envup, at install** |
| git | `hosts/<host>.gitconfig` → `~/.gitconfig.host` | `~/.gitconfig.local` | **envup, at install** |

The split in the last column is the only subtlety. zsh and nvim can ask the machine
its own name and build a path from it. tmux's `source-file` and git's `[include]`
take a literal path and expand nothing, so envup resolves `$ENVUP_HOST` while reading
`meta.sh` — `caps.sh` exports it before any module is sourced — and links this
machine's file to one agreed-upon name:

```bash
LINKS+=("?modules/tmux/files/hosts/${ENVUP_HOST}.conf:$HOME/.tmux/host.conf")
```

The leading `?` is what makes this work everywhere. A `hosts/<host>` file exists on
the one machine it describes and nowhere else, so a required link would fail on every
other machine, forever. `safe_link_optional` skips a missing source and says so at
info level — absence is a fact here, not a fault, and a warning that is always
correct to ignore is a warning people learn to ignore. `doctor --authoring` knows the
same thing and stays quiet about optional sources.

The cost of resolving at install time: adding a **new** host file needs one
`envup install <module>` to pick it up. Editing an existing one does not.

### A fourth layer, for facts envup discovers

git has one more, weaker than all of them: `~/.gitconfig.envup`, rewritten from
scratch on every install. It is where a setting goes when it depends on what this
machine actually has — `delta` as the pager if `bin_path delta` finds one, and
nothing at all if it doesn't.

This exists because the shared `.gitconfig` is read on every machine, so every binary
it names is a bet. It used to name three (`nvim` as the editor, `vimdiff` as the
merge tool, `delta` in `interactive.diffFilter`) and lost all three on a minimal
server — the delta one turning `git diff` itself into an error. The committed file
now names no program; anything that does is either generated from detection or
written by a human who knows which machine they are on.

## Platform detection

There are two detectors — one at install time (`lib/caps.sh`, bash) and one at shell
runtime (`modules/zsh/files/.zshrc.d/20-platform.zsh`, zsh). They can't share a
function (different shells, and the zsh file is symlinked into `$HOME` with no
knowledge of the repo), so they must implement the **same canonical rule**:

| Condition | Platform |
|---|---|
| `uname -s` = Darwin | `macos` |
| Linux + `/proc/version` contains `microsoft` | `wsl2` |
| Linux + (`/.dockerenv` exists **or** `/proc/1/cgroup` has `docker`/`containerd`) | `docker` |
| Linux (otherwise) | `linux` |
| anything else | `linux` (fallback) |

`tests/unit/platform.bats` guards against drift and asserts there are exactly two
implementations. Change both together.

## Adding a module

Create `modules/<name>/meta.sh` (data), optionally `hooks.sh` (functions), and a
`files/` dir. Add the name to a profile. No change to `envup` or `lib/` is needed.
Run `envup doctor --authoring` to validate it. Full walkthrough:
[CONTRIBUTING.md](../CONTRIBUTING.md).

## Commands

`install` · `uninstall` · `upgrade` (`--ref` to pin a tag/branch) · `status`
(`--json`) · `doctor` (`--fix`, `--authoring`, `--module`) · `adopt` · `clean` ·
`log` · `--version`.
