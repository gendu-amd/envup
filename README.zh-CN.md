# envup

> 用一个仓库和一个 CLI 管理一致的终端开发环境。

[![CI](https://github.com/gendu-amd/envup/actions/workflows/ci.yml/badge.svg)](https://github.com/gendu-amd/envup/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-yellow.svg)](LICENSE)
![Platforms](https://img.shields.io/badge/platform-macOS%20%7C%20Linux%20%7C%20WSL2%20%7C%20Docker-blue)

[English](README.md) | **简体中文**

envup 将 shell、编辑器、tmux 和常用 CLI 拆成独立模块统一安装。它既适合
workstation，也适合无 root、代理、离线或共享 HOME 的服务器：已有配置先备份，
无法安装的工具明确降级，所有改动都可检查、可恢复。

## 环境要求

- Bash 4.0 或更高。macOS 先执行 `brew install bash`，envup 会自动找到新版 Bash。
- Git 2.0 或更高。
- macOS、Linux、WSL2 或 Docker。

root、包管理器和网络都不是硬要求；缺少时仍会落好配置，并尽量安装兼容的用户态
release。

## 快速开始

```bash
git clone --recursive https://github.com/gendu-amd/envup.git
cd envup
./envup install                 # 默认 standard profile
# ./envup install --profile full
# ./envup install nvim tmux     # 只装指定模块
exec zsh
```

如果 clone 时漏了子模块：

```bash
git submodule update --init --recursive
```

仓库内使用 `./envup`；安装 zsh 模块后可以在任意目录直接运行 `envup`。

## 命令

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

完整参数看 `envup <command> --help`。

- `install --profile X MODULE...` 安装 profile 与指定模块的并集，自动解析依赖和去重。
- 模块结果分为 `ok`、`degraded`、`skipped`、`failed`。degraded 表示配置已就绪，
  但当前机器装不了工具；只有 failed 会让命令失败。
- `status` 重新检查真实软链和二进制；`doctor --fix` 只修安全、已知的问题并再次验证。
- `upgrade` 更新仓库并重装 manifest 中已有模块。加 `--profile` 可接收 profile 新增
  模块；`--ref v0.1.0` 可固定版本。
- `adopt` 把第三方通过软链追加到托管文件的内容移到 `~/.zshrc.local`，再恢复仓库。
- `clean` 只删模块声明的缓存，不删配置和用户数据。

## Profiles 与模块

| Profile | 内容 | 适用场景 |
|---|---|---|
| `minimal` | zsh、git | 容器和最小服务器 |
| `standard` | minimal + 终端与搜索工具 | 默认开发环境 |
| `full` | standard + nvim、lazygit、yazi | 完整终端 IDE |

| 模块 | 功能 |
|---|---|
| `zsh` | Oh-My-Zsh、Powerlevel10k、补全、alias、Vi 命令行 |
| `git` | 安全的全局默认配置和可选 delta 集成 |
| `tmux` | 多窗口、项目 session、OSC 52 复制、断点恢复 |
| `fzf` | 文件、目录、历史和补全的模糊搜索 |
| `ripgrep` | 遵守 `.gitignore` 的高速递归搜索 |
| `fd` | 更易用的文件搜索，也是 fzf 的数据源 |
| `bat` | 带语法高亮的 `cat` 和预览 |
| `eza` | 带 tree、图标和 Git 状态的现代 `ls` |
| `zoxide` | 按使用频率跳目录：`z` / `zi` |
| `atuin` | SQLite + 模糊搜索的 shell 历史 |
| `delta` | 语法和单词级高亮的 Git diff |
| `direnv` | 进入目录时加载已信任的 `.envrc` |
| `jq` | 处理 API、日志和管道中的 JSON |
| `tealdeer` | 通过 `tldr` 查看常用命令示例 |
| `nvim` | Neovim + NvChad、固定插件、LSP、格式化、session |
| `lazygit` | Git 暂存、历史、分支和 rebase 的终端 UI |
| `yazi` | 高速终端文件管理器；`y` 可保留退出目录 |

Profile 是 [`profiles/`](profiles/) 下的小型 Bash 文件，可以复用已有 profile：

```bash
# profiles/work.sh
use_profile standard
MODULES+=(nvim lazygit)
```

## 日常快捷键

下表中的 `prefix` 指 tmux 的 `Ctrl-a`。

| 操作 | 按键或命令 |
|---|---|
| zsh 插入 → 普通 → 插入模式 | `Esc`，再按 `i` 或 `a` |
| 搜索历史 / 文件 / 目录 | `Ctrl-r` / `Ctrl-t` / `Alt-c` |
| 跳到常用目录 / 交互选择 | `z name` / `zi` |
| 恢复 session / 选择项目 | `tm` / `ts`，或 `prefix f` |
| 跨 tmux pane 和 Nvim split 移动 | `Ctrl-h/j/k/l` |
| tmux 水平 / 垂直分屏 | `prefix -` / `prefix |` |
| 移动当前 tmux window 并跟随 | `prefix <` / `prefix >` |
| 进入 tmux 复制模式 | `prefix v`；`hjkl` 移动、`v` 选择、`y` 复制、`i` 退出 |
| 打开 Nvim 水平 / 垂直 terminal | `Space h` / `Space v` |
| 切换 Nvim 水平 / 垂直 / 浮动 terminal | `Alt-h` / `Alt-v` / `Alt-i` |
| 离开 Nvim terminal 输入 / 查找隐藏 terminal | `Ctrl-x` / `Space pt` |
| 打开 lazygit / Yazi | `lg` / `y` |
| 查看命令示例 | `tldr command`；首次无缓存时执行 `tldr --update` |

tmux 和 Nvim 使用 OSC 52，让远端复制内容沿 SSH 到本地 terminal。VS Code 和
Cursor 需要设置 `terminal.integrated.enableClipboardWrite: true`。如果当前机器有
`pbcopy`、`wl-copy`、`xclip` 或 `clip.exe`，会优先使用本机剪贴板工具。

tmux 每五分钟保存一次。`tm` 会启动 tmux、等待恢复完成再进入。`ts` / `prefix f`
默认搜索 `~/work`、`~/src`、`~/projects` 等常见目录，可通过
`ENVUP_PROJECT_DIRS` 或 `~/.config/envup/project-dirs` 修改。

## Nvim

nvim 模块要求 Neovim 0.10+。老 glibc 服务器会使用兼容的 v0.10 release，避免装上
却无法启动。也可以使用 `conda install -c conda-forge neovim`。

默认语言工具：

| 语言 | LSP | Formatter |
|---|---|---|
| C / C++ | clangd | clang-format |
| Python | pyright | Ruff |
| Lua | lua-language-server | StyLua |
| shell | bash-language-server | shfmt |
| JSON / YAML / Markdown | — | Prettier |

| 操作 | 按键 |
|---|---|
| 定义 / 声明 | `gd` / `gD` |
| 引用 / 实现 / 类型定义 | `gr` / `gi` / `gy` |
| 悬浮信息 / 函数签名 | `K` / `Space lh` |
| 重命名 / Code Action | `Space rn` / `Space ca` |
| 当前文件 / 工作区符号 | `Space ls` / `Space lS` |
| 上一个 / 下一个 / 完整诊断 | `[d` / `]d` / `Space df` |
| 手动格式化 | `Space fm` |

第一次 `K` 打开悬浮窗，再按 `K` 聚焦；悬浮窗内按 `K` 或 `Ctrl-w p` 回源码，
`Esc` 关闭。LSP 未连接或没有结果时会明确提示。

保存时只在项目存在 `.clang-format`、`pyproject.toml`、`.stylua.toml` 等风格文件时
自动格式化。设置 `vim.g.envup_format_always = true` 可无条件格式化。默认超过
1.5 MB 的文件会关闭昂贵功能；设置 `vim.g.envup_bigfile_bytes = 0` 可禁用该保护。

### Docker 编译、Host 使用 Nvim

Docker 生成的 `compile_commands.json` 使用容器绝对路径，Host clangd 不能直接使用。
在 Host 的项目根目录执行：

```bash
envup clangd sync
envup clangd status
# 只有自动选择容器存在歧义时才传 --container NAME
```

envup 从 Docker mount 自动推导路径映射，只生成一份 Host 视角缓存，不修改原 build
目录。同步后执行 `:LspRestart`；Docker 重新 configure 后再 sync，数据库过期时 Nvim
会提示。数据库不在项目或 `build/` 常见位置时使用
`envup clangd sync --database PATH`。

## 配置模型

托管配置从各模块 `files/` 目录软链到 HOME。目标已存在时先移到
`~/.dotfiles_backup/<timestamp>/`，并保留相对路径。重复安装是幂等的；卸载只删除
当前仓库拥有的软链。

需要同步的机器专属配置使用仓库提供的 host 模板：

| 模块 | 纳入版本管理的 host 层 | 私有最终覆盖层 |
|---|---|---|
| zsh | `modules/zsh/files/.zshrc.d/hosts/<host>.zsh` | `~/.zshrc.local` 或 `~/.zshrc.local.<host>` |
| tmux | `modules/tmux/files/hosts/<host>.conf` | `~/.tmux.local` |
| nvim | `modules/nvim/files/hosts/<host>.lua` | `~/.config/nvim/local.lua` |
| git | `modules/git/files/hosts/<host>.gitconfig` | `~/.gitconfig.local` |

例如把 `modules/tmux/files/hosts/example.conf.template` 复制为当前 hostname，再执行
`envup install tmux`。凭证和临时实验只放仓库外的私有层。

## 环境变量

全部可选。

| 变量 | 默认 | 作用 |
|---|---|---|
| `ENVUP_DRY_RUN` | `0` | 只预览改动；CLI 的 `--dry-run` 会设置它。 |
| `ENVUP_OFFLINE` | `0` | 不尝试联网，但仍安装配置。 |
| `ENVUP_GH_MIRROR` | — | GitHub release、clone 和 raw URL 的镜像前缀。 |
| `ENVUP_REQUIRE_CHECKSUM` | `0` | 没有匹配的上游摘要时拒绝下载结果。 |
| `ENVUP_LOCAL_BIN` | `~/.local/bin` | 用户态二进制安装目录。 |
| `ENVUP_LOCAL_OPT` | `~/.local/opt` | 完整应用目录的用户态安装位置。 |
| `ENVUP_BACKUP_DIR` | 带时间戳目录 | 被替换链接目标的备份根目录。 |
| `ENVUP_STATE_DIR` | `~/.local/state/envup` | manifest、日志和 adopt 状态；共享 HOME 时按 host 隔离。 |
| `ENVUP_LOG_DIR` | `$ENVUP_STATE_DIR/logs` | 日志目录。 |
| `ENVUP_LOG_FILE` | 带时间戳文件 | 当前命令日志；设为 `/dev/null` 可禁用。 |
| `ENVUP_LOG_LEVEL` | `info` | 终端级别：`debug`、`info`、`warn`、`error`。 |
| `ENVUP_MODULE_TIMEOUT` | `900` | 每个模块 hook 的看门狗秒数。 |
| `ENVUP_NET_TIMEOUT` | `120` | 每次 Git 操作的超时秒数。 |
| `ENVUP_NET_TIMEOUT_NVIM` | `600` | Nvim 插件恢复超时。 |
| `ENVUP_NET_TIMEOUT_INSTALLER` | `300` | 厂商安装脚本超时。 |
| `ENVUP_NET_KILL_AFTER` | `10` | 超时到强制结束之间的宽限秒数。 |
| `ENVUP_NET_PROBE_TIMEOUT` | `5` | 网络能力探测超时。 |
| `ENVUP_PRIV_KEEP_ENV` | 自动 | 强制 (`1`) 或禁用 (`0`) `sudo -E`。 |
| `ENVUP_EDITOR` | 自动 | 在 nvim/vim/vi/nano 之前尝试的编辑器。 |
| `ENVUP_PLATFORM` | 自动 | 强制为 `macos`、`linux`、`wsl2` 或 `docker`。 |
| `ENVUP_NVIM_LAZY` | `restore` | Nvim 插件使用 `restore`、`sync` 或 `skip`。 |
| `ENVUP_ATUIN_INSTALL` | — | 设为 `skip` 跳过 Atuin。 |
| `ENVUP_ZSH_QUIET` | `0` | 隐藏 zsh 配置切片加载警告。 |
| `ENVUP_PROJECT_DIRS` | 常见目录 | 项目选择器使用的冒号分隔 glob。 |
| `ENVUP_TMUX_SESSION` | `main` | 没有可恢复布局时创建的 session 名。 |
| `ENVUP_TMUX_RESTORE_WAIT` | `8` | `tm` 等待恢复的秒数。 |
| `ENVUP_TS_POPUP` | 自动 | 强制 (`1`) 或禁用 (`0`) tmux popup。 |

## 可靠性与排障

安装引擎会探测 OS、发行版、架构、libc、权限、包管理器和网络，并依次尝试系统包、
兼容的 GitHub release、Git/厂商安装器，最后给出人工安装提示。下载、包管理器和模块
hook 都有超时；会改机器状态的命令把日志写到 `$ENVUP_STATE_DIR/logs`。

探测结果以 `ENVUP_OS`、`ENVUP_PLATFORM`、`ENVUP_DISTRO`、
`ENVUP_DISTRO_VER`、`ENVUP_DISTRO_LIKE`、`ENVUP_ARCH`、`ENVUP_LIBC`、
`ENVUP_PRIV`、`ENVUP_PKG`、`ENVUP_NET`、`ENVUP_HOST` 和
`ENVUP_HOME_SHARED` 提供给模块 hook。它们应视为只读事实；只有
`ENVUP_PLATFORM` 支持用户覆盖。

```bash
envup doctor                 # 解释当前机器的问题
envup doctor --fix           # 修复后重新验证
envup log                    # 最近一次操作日志
ENVUP_LOG_LEVEL=debug envup install nvim
```

常见处理：

- 主题或插件缺失：`git submodule update --init --recursive`，然后重装模块。
- 仓库移动或软链悬空：在新 checkout 运行 `envup doctor --fix`。
- 托管文件被第三方追加：升级前运行 `envup adopt`。
- Nvim 插件状态异常：`envup clean nvim && envup install nvim`。
- macOS 没有 timeout：`brew install coreutils` 提供 `gtimeout`。
- 模块 degraded：安装提示中的系统依赖，或网络/root 可用后重跑；配置已经链接。

CI 覆盖 macOS、Ubuntu/Debian、Fedora/CentOS、WSL2、Docker、无 root、离线和
Bash 4.2。Arch 与 Alpine 为尽力支持，具体包可用性仍取决于平台。

## 架构与开发

`envup` 负责命令分发；[`lib.sh`](lib.sh) 按职责加载能力探测、文件安全、网络、
provider、模块规划、健康检查和升级逻辑。模块由声明式 `meta.sh`、可选的函数式
`hooks.sh` 和软链配置 `files/` 组成；profile 只组合模块名。

模块契约、检查和发布流程见 [CONTRIBUTING.md](CONTRIBUTING.md)，版本变化见
[CHANGELOG.md](CHANGELOG.md)。

## 许可证

MIT —— 见 [LICENSE](LICENSE)。
