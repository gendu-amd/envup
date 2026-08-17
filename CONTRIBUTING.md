# Contributing to envup

envup is intentionally small: a CLI (`envup`) that dispatches, a library
(`lib.sh` + `lib/`), and a directory of modules. Most contributions are
**a new module** — and a module is usually pure data with no code at all.

## Add a module

Create `modules/<name>/`:

```
modules/<name>/
├── meta.sh        # declarative metadata — the whole module, usually
├── hooks.sh       # optional: custom steps, as functions
└── files/         # configs to symlink into $HOME
```

### `meta.sh` — data, not code

It is sourced for its variables and never executed for effect. The engine
(`lib/engine.sh`) reads it and does the work.

```bash
NAME="<short label>"
DESCRIPTION="<one line, shown by 'envup status'>"
DEPENDS=(<module>...)          # other modules, installed before this one

# --- how to install it, in order of preference ---------------------------
PROVIDERS=(system github_release script)
GH_REPO="owner/repo"           # for github_release
SCRIPT_URL="https://..."       # for script
GIT_URL="https://..."          # for git
PKG_NAMES=("apt:fd-find" "dnf:fd-find")   # per packaging family; "-" = no such package
PKG_DEFAULT="fd"               # fallback package name (defaults to $NAME)

# --- how to know it worked ------------------------------------------------
VERIFY_BIN="<binary>"          # unverified is not installed
VERIFY_MIN_VERSION="0.9.0"     # optional
VERIFY_VERSION_ARG="-V"        # optional; default --version

# --- what to link ---------------------------------------------------------
LINKS=("modules/<name>/files/.foorc:$HOME/.foorc")   # "?" prefix = optional source
# a per-machine layer, if the tool's config differs between boxes:
LINKS+=("?modules/<name>/files/hosts/${ENVUP_HOST}.foorc:$HOME/.foorc.host")

APPLIES_IF='...'               # shell condition; false ⇒ 'skipped', not 'failed'
CLEAN_PATHS=(<path>...)        # caches 'envup clean <name>' removes (never config!)
```

`$ENVUP_HOST` (short hostname) is exported before `meta.sh` is sourced, which is
what makes that second line possible. Use it when the tool's own config format
cannot expand a hostname — tmux's `source-file` and git's `[include]` both take a
literal path, so envup resolves the name here and links to one fixed target that
the committed config then reads unconditionally. The `?` is not optional: the
file exists on one machine and is absent on all the others, and a required link
would fail everywhere else forever. Ship a
`files/hosts/example.<ext>.template` alongside it.

Pick providers by how the tool is actually distributed:

| Provider | Use when | Needs root? |
|---|---|---|
| `system` | the distro packages it | yes (brew excepted) |
| `github_release` | it ships prebuilt binaries — **the route that works on a server without root** | no |
| `git` | it's distributed as a checkout with its own installer (fzf) | no |
| `script` | the vendor's official `curl \| sh` is the only route | no |
| `manual` | it needs a compiler; print instructions and degrade | — |

List them best-first. The engine walks the chain and takes the first one that
can work given the detected privilege, network and architecture. A module whose
tool can't be installed here ends up `degraded` — config linked, tool missing —
which is a correct outcome, not a failure.

The engine verifies by running `$VERIFY_BIN $VERIFY_VERSION_ARG` and checking the
**exit status** — a binary that is present but won't execute (wrong libc, wrong
arch) is not installed, and the chain keeps going. So `VERIFY_VERSION_ARG` has to
be a flag the tool actually answers on: tmux before 3.1 prints usage and exits 1
for `--version`, hence `VERIFY_VERSION_ARG="-V"`. If the tool has no version flag
at all, define `verify()` in `hooks.sh` to replace the check wholesale.

### `hooks.sh` — only if there are custom steps

Define **functions**: `pre_install`, `post_install`, `pre_uninstall`,
`post_uninstall`. Functions rather than a bare script because hooks are sourced
into a non-function subshell, where a top-level `local` is a syntax error.

Every `lib/` helper is available. Use them instead of raw commands:

| Helper | What it does |
|--------|--------------|
| `pkg_install <pkg>...` | install system packages (apt/dnf/yum/pacman/brew/apk), honouring privilege detection |
| `have <cmd>` | is a command on PATH? |
| `bin_path <cmd>` / `bin_version <cmd>` | resolve a binary (including `~/.local/bin`) / read its version |
| `safe_link <src> <dst>` | symlink `<src>` → `<dst>`, backing up any existing real file. `<src>` is relative to the repo root. |
| `safe_link_optional <src> <dst>` | same, but skip silently if `<src>` is missing |
| `unlink_safe <dst>` | remove a symlink **only if** it points into the repo |
| `net_run "<desc>" -- <cmd>...` | run a network command with a timeout |
| `net_fetch <url> [dst]` / `net_clone <url> <dst>` | download / clone through the mirror, proxy, offline check and timeout |
| `gh_url <url>` | rewrite a GitHub URL through `ENVUP_GH_MIRROR` |
| `priv_run <cmd>...` | run with elevated privilege **if** it's available without a password |
| `block_set <file> <tag>` / `block_del <file> <tag>` | idempotently insert/remove a marker-delimited block in a file you append to but don't own (e.g. `~/.bashrc`); content on stdin |
| `submodule_ensure <mod> <dir>...` | init git-submodule plugins + verify they're non-empty (zsh/tmux) |
| `log_step/info/success/warn/error/hint "<msg>"` | logging |

Every helper honours `ENVUP_DRY_RUN`, so a correct hook works under `--dry-run`
for free. Example:

```bash
# modules/foo/hooks.sh
post_install() {
    [[ -d "$HOME/.config/foo" ]] || mkdir -p "$HOME/.config/foo"
    log_success "foo configured"
}
```

**Never call `curl`, `wget` or `git clone` directly.** They bypass the mirror,
the proxy, the offline check and the timeout — `envup doctor --authoring`
rejects them. Use `net_fetch` / `net_clone`.

**Document the module.** Every module should be understandable at a glance:

- `meta.sh` starts with a `# Module: <name> — <one-line purpose + notable side
  effects>` header, and sets a `DESCRIPTION` (shown by `envup status`).
- `hooks.sh` opens with a short comment on what it does and any non-obvious
  decisions (e.g. why a step is guarded, what is deliberately kept).
- For anything richer (key bindings, cheatsheets), add `docs/<topic>.md` and link
  it from the README (see `docs/TMUX.md`).

**Add it to a profile** in `profiles/<name>.sh` (`MODULES=(...)`). That's it —
no change to `envup` or `lib/` is needed.

## Conventions

- A pre-existing real file at a link target is **always backed up** (never
  overwritten). Don't add prompts or overwrite logic.
- Uninstall removes envup's own symlinks. Don't remove the system package or
  user data.
- Nothing may block on input. No `sudo` prompt, no `read`. If a privilege isn't
  available without a password, take another route or degrade.
- `envup doctor --authoring` must pass. It catches leftover v1 `install.sh`
  files, hand-rolled downloads, unknown providers, executable statements in
  `meta.sh`, and `CLEAN_PATHS` that would delete user data.
- Test with `--dry-run` against a throwaway `HOME`:

```bash
HOME=$(mktemp -d) ./envup install <name> --dry-run
```

- Then test the paths that actually break. A no-root container is one command:

```bash
docker run --rm -v "$PWD:/src:ro" ubuntu:24.04 bash -c '
  apt-get update -qq && apt-get install -y -qq git >/dev/null && useradd -m t &&
  cp -a /src /home/t/envup && chown -R t /home/t/envup &&
  su t -c "cd /home/t/envup && ./envup install <name> && ./envup doctor"'
```

## Tests & linting

envup has a test + lint harness (run these before opening a PR — CI runs the
same checks on Linux and macOS):

```bash
scripts/lint.sh    # shellcheck + bash -n over all first-party shell sources
scripts/test.sh    # bats unit + dry-run integration suites
```

Requirements: [`shellcheck`](https://www.shellcheck.net/) and
[`bats`](https://github.com/bats-core/bats-core) on `PATH`.

- **Unit tests** (`tests/unit/`) cover the library, one file per concern:
  `caps` (privilege/network/arch detection), `engine` + `providers` (the install
  contract), `realpath` / `link` / `unlink` (path ownership, including
  symlinked-home cases), `manifest`, `health`, `doctor`, `adopt`, and
  `zshconfig` (which starts real interactive zsh shells to assert slice order,
  PATH dedup and the conditional locale/EDITOR behaviour). Add a case when you
  change these. Several cover shipped config rather than library code:
  `hosts` (the per-machine layer across all four modules, and its load order),
  `gitconfig` (that the committed config names no binary, and the generated
  `~/.gitconfig.envup` lifecycle), `clipboard` (the OSC 52 settings, each of
  which fails silently when wrong), `tmuxrestore` (the login hook, the
  per-machine resurrect directory, and nvim's `Session.vim`), `searchtools`
  (ripgrep / fd / delta, whose whole difficulty is that the package, the binary
  and the module go by three different names), `shelltools` (eza, bat and
  direnv — a second name on Debian, a crippled second *build* upstream, and a
  bare binary with no archive around it), `checksum` (digest computation
  across the three tools that exist, the three checksum-file layouts upstreams
  use, and the difference between "mismatch" and "nothing to compare against"),
  and `nvimconfig` (the editor
  config as text — nothing there runs neovim, because the machines this repo
  targets are exactly the ones where it may not start). `tmuxrestore`
  runs the login hook on a real terminal via zsh's own `zsh/zpty` — a hook whose
  job is to decide whether it is talking to a person cannot be tested from a
  pipe, where every guard trips and every test passes for the wrong reason.
- **Scripts under `modules/*/files/bin/`** are first-party sources: `lint.sh`
  covers them, and they get behavioural tests, not grep tests — see
  `tests/unit/sessionizer.bats`, which stubs `tmux` and `fzf` to exercise the
  failure paths a key binding has no way to report.
- **Integration** (`tests/integration/`): `dry-run.bats` asserts every profile
  installs side-effect free; `doctor.bats` validates the authoring rules against
  fixture modules; `smoke.sh` does a real install→status→uninstall of the `git`
  module in a throwaway `HOME`.
- CI additionally runs the two environments that used to break: an
  **unprivileged container** (must install via `github_release` and degrade, not
  fail) and an **offline** run (must decline immediately, not hang).
- Any behavior change must keep the core invariants intact (backup / idempotent
  / reversible / dry-run / dependency order / single source of truth / never
  block on input) — the unit suite guards them.
- `zsh` is a test dependency, not just a module. Without it `zshconfig.bats`
  skips, and a silently skipped suite is the same as no suite.

## Releasing

1. Update [`CHANGELOG.md`](CHANGELOG.md): move `[Unreleased]` items under a new
   `[X.Y.Z]` heading (dated).
2. Bump [`VERSION`](VERSION) to `X.Y.Z` (drop the `-dev` suffix).
3. Commit (`chore: release vX.Y.Z`) and tag: `git tag -a vX.Y.Z -m "vX.Y.Z"`.
4. Users pin to it with `envup upgrade --ref vX.Y.Z`.

`envup --version` reads `VERSION` (falling back to `git describe --tags`).
