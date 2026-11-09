# envup

[![CI](https://github.com/gendu-amd/envup/actions/workflows/ci.yml/badge.svg)](https://github.com/gendu-amd/envup/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-yellow.svg)](LICENSE)

**English** | [简体中文](README.zh-CN.md)

envup restores a familiar terminal environment on macOS, Linux, WSL2 and Docker.
One CLI manages independent shell, Git, tmux, editor and search-tool modules.
Existing configuration is backed up; private identity, history, sessions and
project toolchains remain yours.

## Requirements

- Bash 4.0+ and Git 2.0+. On macOS, run `brew install bash`; envup finds it.
- Writable configuration and installation directories.

Root and network access are optional. Available providers determine which tools
can be supplied; linked configuration alone does not mean the workflow is ready.

## Quick start

```bash
git clone --recursive https://github.com/gendu-amd/envup.git
cd envup
./envup install --dry-run       # preview the standard selection
./envup install
./envup status
./envup doctor
exec zsh                       # load the config when zsh is available
```

If cloned without submodules, run `git submodule update --init --recursive`.
Use `./envup` in the checkout, or `envup` after installing the zsh module.
The zsh module sets up Oh-My-Zsh, Powerlevel10k, Vi mode and a Bash-to-zsh entry
block; where permitted it also changes the login shell. Install individual tools
if you keep another shell, then configure PATH and integrations yourself.

## Choose tools

| Profile | Contents |
|---|---|
| `minimal` | zsh, git |
| `standard` (default) | minimal + terminal, search and CLI tools |
| `full` | standard + nvim, lazygit, yazi |

```bash
./envup install --profile full
./envup install nvim tmux       # selected modules only
```

A profile plus named modules installs their union. See the [module list](docs/guide.md#profiles-and-modules).

## Daily use

| Task | Entry |
|---|---|
| Resume tmux / choose a project | `tm` / `ts` |
| Search text / files / history | `rg` / `Ctrl-t` / `Ctrl-r` |
| Jump to a directory | `z name` / `zi` |
| Edit / inspect Git changes | `nvim file` / `lg` |
| Move between tmux panes and Nvim splits | `Ctrl-h/j/k/l` |
| Leave tmux, keeping tasks running | `Ctrl-a`, then `d` |

Shortcuts are enabled when the corresponding tools are available.
See [all shortcuts](docs/guide.md#daily-shortcuts) and [Nvim](docs/guide.md#nvim).

## Private configuration

| File | Settings |
|---|---|
| `~/.gitconfig.local` | Git name, email and private overrides |
| `~/.zshrc.local` | Shell settings and PATH |
| `~/.tmux.local` | tmux overrides |
| `~/.config/nvim/local.lua` | Editor overrides |
| `~/.config/nvim/envup.json` | Plugin/language selection |

Nvim uses `XDG_CONFIG_HOME` when set. For example, `{"languages":["c","cpp"]}`
selects C/C++ support; omitting this selection keeps the full default set.
Restart Nvim and run `envup install nvim` after changing it.
Edit private files for personal settings: shared file links edit this checkout.
See [configuration and ownership](docs/guide.md#configuration-model).

## Check and maintain

```bash
envup status                   # current capability and last installation outcome
envup doctor --module nvim
envup doctor --fix              # repair managed parts and re-check
envup upgrade --tools reuse     # update checkout and recorded modules
```

Inspect `degraded`, `skipped` and failed results. Test navigation/clipboard in the
actual project and terminal; install success alone does not establish readiness.
Full `doctor --fix` may fetch missing submodules. Nvim component restoration uses
`envup install nvim`; `clean nvim` preserves plugins and language tools.

Uninstall removes owned integration, retaining user data, reused tools and backups.
Clean removes declared disposable caches. Neither automatically restores old config.
Checkout, package, installer and plugin changes have separate recovery boundaries.

## Reference

- [Guide](docs/guide.md): commands, modules, editor, configuration and troubleshooting.
- [Environment variables](docs/guide.md#environment-variables).
- [Host Nvim and Docker builds](docs/guide.md#docker-builds-with-host-side-nvim).
- [Acceptance and platform limits](docs/guide.md#functional-and-platform-acceptance).
- [Contributing](CONTRIBUTING.md): architecture, module contracts, checks and releases.
- [Changelog](CHANGELOG.md): this checkout's changes; unreleased work stays on `main`.

MIT — see [LICENSE](LICENSE).
