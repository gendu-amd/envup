# Contributing to envup

envup is intentionally small: a CLI (`envup`), one shared library (`lib.sh`),
and a directory of modules. Most contributions are **a new module**.

## Add a module

Create `modules/<name>/`:

```
modules/<name>/
├── meta.sh        # metadata (all fields optional)
├── install.sh     # install hook
├── uninstall.sh   # uninstall hook
└── files/         # configs to symlink into $HOME
```

**`meta.sh`** — declare any of:

```bash
NAME="<short label>"
DESCRIPTION="<one line, shown by 'envup status'>"
DEPENDS=(<module>...)      # installed before this one
SELF_DEPS=(<binary>...)    # system commands the install hook needs (curl, git)
CLEAN_PATHS=(<path>...)    # caches 'envup clean <name>' removes (never config!)
```

**`install.sh`** — runs in a subshell that already has every `lib.sh` helper.
Use them instead of raw commands:

| Helper | What it does |
|--------|--------------|
| `pkg_install <pkg>...` | install system packages (any of apt/dnf/yum/pacman/brew/apk) |
| `pkg_have <cmd>` / `have <cmd>` | is a command on PATH? |
| `safe_link <src> <dst>` | symlink `<src>` → `<dst>`, backing up any existing real file. `<src>` is relative to the repo root. |
| `safe_link_optional <src> <dst>` | same, but skip silently if `<src>` is missing |
| `unlink_safe <dst>` | remove a symlink **only if** it points into the repo |
| `net_run "<desc>" -- <cmd>...` | run a network command with a timeout (`-k` SIGKILL backstop) |
| `block_set <file> <tag>` / `block_del <file> <tag>` | idempotently insert/remove a marker-delimited block in a file you append to but don't own (e.g. `~/.bashrc`); content on stdin |
| `submodule_ensure <mod> <dir>...` | init git-submodule plugins + verify they're non-empty (zsh/tmux) |
| `log_step/info/success/warn/error/hint "<msg>"` | logging |

Every helper honours `ENVUP_DRY_RUN`, so a correct hook works under
`--dry-run` for free. Example:

```bash
# modules/foo/install.sh
pkg_have foo || pkg_install foo || return 1
safe_link "modules/foo/files/.foorc" "$HOME/.foorc" || return 1
log_success "foo installed"
```

**`uninstall.sh`** — undo the symlinks with `unlink_safe`. Don't remove the
system package or user data.

**Document the module.** Every module should be understandable at a glance:

- `meta.sh` starts with a `# Module: <name> — <one-line purpose + notable side
  effects>` header, and sets a `DESCRIPTION` (shown by `envup status`).
- `install.sh` / `uninstall.sh` open with a short comment on what they do and any
  non-obvious decisions (e.g. why a step is guarded, what is deliberately kept).
- For anything richer (key bindings, cheatsheets), add `docs/<topic>.md` and link
  it from the README (see `docs/TMUX.md`).

**Add it to a profile** in `profiles/<name>.sh` (`MODULES=(...)`). That's it —
no change to `envup` or `lib.sh` is needed.

## Conventions

- A pre-existing real file at a link target is **always backed up** (never
  overwritten). Don't add prompts or overwrite logic.
- If your hook uses `local`, wrap the body in a function (hooks are sourced
  into a non-function subshell, where top-level `local` is illegal).
- Test with `--dry-run` against a throwaway `HOME`:

```bash
HOME=$(mktemp -d) ./envup install <name> --dry-run
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

- **Unit tests** (`tests/unit/`) cover `lib.sh` core logic: dependency
  resolution, safe-linking/backup, manifest, and managed blocks. Add a case
  when you change these.
- **Integration** (`tests/integration/`): `dry-run.bats` asserts every profile
  installs side-effect free; `smoke.sh` does a real install→status→uninstall of
  the `git` module in a throwaway `HOME`.
- Any behavior change must keep the six core invariants intact (backup /
  idempotent / reversible / dry-run / dependency order / single source of truth)
  — the unit suite guards them.

## Releasing

1. Update [`CHANGELOG.md`](CHANGELOG.md): move `[Unreleased]` items under a new
   `[X.Y.Z]` heading (dated).
2. Bump [`VERSION`](VERSION) to `X.Y.Z` (drop the `-dev` suffix).
3. Commit (`chore: release vX.Y.Z`) and tag: `git tag -a vX.Y.Z -m "vX.Y.Z"`.
4. Users pin to it with `envup upgrade --ref vX.Y.Z`.

`envup --version` reads `VERSION` (falling back to `git describe --tags`).
