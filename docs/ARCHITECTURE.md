# envup architecture

envup keeps your shell/editor/terminal setup consistent across machines. The
whole tool is **two files** plus a directory of modules.

```
envup           # CLI: one cmd_* function per command + dispatch (~250 lines)
lib.sh          # all shared helpers, sourced by the CLI and by module hooks
modules/<name>/
  meta.sh       # NAME / DESCRIPTION / DEPENDS / SELF_DEPS / CLEAN_PATHS
  install.sh    # install hook  — calls safe_link / pkg_install / log_* / ...
  uninstall.sh  # uninstall hook — calls unlink_safe / ...
  files/        # configs that get symlinked into $HOME
profiles/<name>.sh   # MODULES=(...)   — a named set of modules
```

## How it works

`envup install [profile|modules]` →

1. Resolve the module set (a profile's `MODULES`, and/or names on the CLI).
2. `resolve_order` puts each module's `DEPENDS` before it (deduped).
3. Install any missing `SELF_DEPS` (e.g. `curl`, `git`) up front.
4. Run each module's `install.sh` in a subshell that inherits `lib.sh`'s
   helpers. The hook symlinks its `files/` into `$HOME` via `safe_link`.
5. Record the module in the manifest (`~/.local/state/envup/installed`).

**Configs are symlinks**, not copies — edit the file in the repo (or
`git pull` on another machine) and the change is live immediately, no reinstall.

A few binary tools (fzf, zoxide, atuin) ship no config files: they're installed
by their hook and wired into zsh via `.zshrc.d/tools.zsh`. nvim is the
exception that needs reproducibility across nvim versions, so its plugin set is
pinned by a committed `lazy-lock.json` and restored on install.

## Key guarantees (all in `lib.sh`)

- **Backup, never clobber.** `safe_link` moves any pre-existing *real* file at
  a link target into `~/.dotfiles_backup/<timestamp>/` before linking.
- **Idempotent.** Re-running install is a no-op for already-correct symlinks.
- **Reversible.** `unlink_safe` (and so `envup uninstall`) only removes
  symlinks that point inside the repo — never your own files.
- **Cross-platform.** `lib.sh` detects the platform and one of
  apt/dnf/yum/pacman/brew/apk; `pkg_install` wraps it.
- **No step can wedge the whole run.** `net_run` wraps git/curl with `timeout`,
  `pkg_install` wraps the package manager, and `run_module_hook` puts an **outer
  watchdog** (`ENVUP_MODULE_TIMEOUT`, default 900s, SIGTERM then SIGKILL) around
  every hook. A module that hangs — stuck mirror, forgotten `net_run`, a step
  waiting on stdin — is killed and reported failed; the sequential install then
  moves on to the next module instead of hanging forever. (Requires a
  `timeout`/`gtimeout` binary; without one envup warns and runs unguarded.)
- **Dry-run.** `ENVUP_DRY_RUN=1` / `--dry-run` previews every change.

## Platform detection

There are two detectors — one at install time (`lib.sh`, bash) and one at shell
runtime (`modules/zsh/files/.zshrc.d/platform.zsh`, zsh). They can't share a
function (different shells, and the zsh file is symlinked into `$HOME` with no
knowledge of the repo), so they must implement the **same canonical rule**:

| Condition | Platform |
|---|---|
| `uname -s` = Darwin | `macos` |
| Linux + `/proc/version` contains `microsoft` | `wsl2` |
| Linux + (`/.dockerenv` exists **or** `/proc/1/cgroup` has `docker`/`containerd`) | `docker` |
| Linux (otherwise) | `linux` |
| anything else | `linux` (fallback) |

`tests/unit/platform.bats` guards against drift (checks `lib.sh` against this
rule and that `platform.zsh` uses the same discriminators). Change both together.

## Mirrors / restricted networks

`gh_url` (`lib.sh`) rewrites envup's own GitHub downloads through
`ENVUP_GH_MIRROR` (a proxy prefix, e.g. `https://ghproxy.com`) when set;
otherwise it returns URLs unchanged. `init.lua` honors the same variable for
nvim's first-launch lazy.nvim bootstrap. Submodules use git's `insteadOf`.

## Adding a module

Create `modules/<name>/` with `meta.sh`, `install.sh`, `uninstall.sh`, and a
`files/` dir. Use the helpers from `lib.sh` (`safe_link`, `pkg_install`,
`log_*`). Add the name to a profile in `profiles/` (compose with `use_profile`).
No change to `envup` or `lib.sh` is needed. Run `envup doctor` to validate the
module follows the conventions (meta fields, function-wrapped hooks, safe
`CLEAN_PATHS`).

## Commands

`install` · `uninstall` · `upgrade` (update + reinstall; `--ref` to pin a
tag/branch) · `status` (`--json`) · `clean` (remove the `CLEAN_PATHS` a module
declares) · `log` · `doctor` (validate modules) · `--version`.
