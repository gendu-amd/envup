# envup

> 一个仓库、一个 CLI、一条命令 —— 跨平台的开发环境。

[![CI](https://github.com/gendu-amd/envup/actions/workflows/ci.yml/badge.svg)](https://github.com/gendu-amd/envup/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
![Platforms](https://img.shields.io/badge/platform-macOS%20%7C%20Linux%20%7C%20WSL2%20%7C%20Docker-blue)
![Shell](https://img.shields.io/badge/shell-bash%20%E2%89%A5%204-green)

[English](README.md) | **简体中文**

一个模块化的 dotfiles 管理器：用一条命令在任意新机器上装好你的 shell、编辑器与 CLI 工具。可以按 profile（minimal / standard / full）安装，也可以只装单个模块；不想要的随时卸载；全程有日志、可回滚。

## 环境要求

- **bash ≥ 4.0**（模块依赖解析用到关联数组）。**macOS** 的 `/bin/bash` 仍是 3.2 —— 先 `brew install bash` 一次；`./envup` 会自动识别 Homebrew 的 bash（你的登录 shell / tmux shell 仍可用 zsh）。
- **git ≥ 2.0**
- **POSIX 系统**：macOS、Linux（Ubuntu/Debian/Fedora/CentOS/Arch/Alpine）、WSL2 或 Docker
- **包管理器**：apt / dnf / yum / pacman / brew / apk 之一
- 首次安装需要**网络**（下载 zsh 插件、atuin/fzf 等可选工具）
- 若缺系统包需要 **sudo**
- 建议把 `~/.local/bin` 加入 `$PATH`，安装后即可全局使用 `envup`

## 快速开始

```bash
# 克隆（带子模块 —— zsh 主题/tmux 插件需要）
git clone --recursive https://github.com/gendu-amd/envup.git
cd envup

# 忘了 --recursive？补一下：
#   git submodule update --init --recursive

# 安装 standard profile（zsh, git, tmux, fzf, zoxide, atuin）
./envup install

# 或选更小的 profile
./envup install --profile minimal

# 或只装你需要的
./envup install zsh git

# 开个新 shell
exec zsh
```

## 命令

```bash
./envup install [--profile NAME] [--dry-run] [MODULE...]     # 安装
./envup uninstall [--all] [--dry-run] MODULE...              # 卸载
./envup upgrade [--profile NAME] [--ref TAG] [--dry-run] ...  # 更新 + 重装
./envup status [--json]                                      # 查看已安装（✓ / ○）
./envup clean [--dry-run] [--all | MODULE...]               # 清理 meta 声明的缓存
./envup log [--tail]                                        # 最近一次命令的日志
./envup doctor [--module NAME]                              # 校验模块规范
./envup --version                                           # 打印版本
```

用 `./envup <command> --help` 查看各命令选项。几个不那么显然的语义：

- `install --profile X MODULE...` 是**并集**，不是二选一。
- `upgrade` 默认只重装 manifest 里已有的模块；用 `--profile` 可纳入 profile 新增的模块。
- `upgrade --ref v0.1.0` 会切到指定 tag/分支（fetch + checkout + 子模块），用于**钉版本**。
- `status --json` 输出机器可读状态，便于脚本编排。
- `ENVUP_LOG_LEVEL=debug|info|warn|error`（默认 `info`）控制终端输出详略；日志文件始终记录全量。
- `ENVUP_GH_MIRROR=https://ghproxy.com` 让 envup 自身的 GitHub 下载走镜像/代理（受限网络友好）；不设置则行为不变。子模块用 git 的 `insteadOf`。
- `envup doctor` 静态校验每个模块（元数据字段、钩子是否 function 包裹、`DEPENDS` 是否存在、`CLEAN_PATHS` 是否误含用户数据）。

## Profiles

| Profile | 模块 | 场景 |
|---------|------|------|
| `minimal` | `zsh git` | 裸服务器、无头容器 |
| `standard`（默认） | `+ tmux fzf zoxide atuin` | 典型开发机 |
| `full` | `+ nvim` | 高级工作站 |

Profile 通过 `use_profile` **组合**，每层只写自己新增的部分：

```bash
# profiles/standard.sh = minimal + 终端工具
use_profile minimal
MODULES+=(tmux fzf zoxide atuin)

# profiles/full.sh = standard + 编辑器
use_profile standard
MODULES+=(nvim)
```

## 模块

每个模块是 [`modules/`](modules/) 下一个自包含目录：

```
modules/<name>/
├── meta.sh        # NAME / DESCRIPTION / DEPENDS / SELF_DEPS / CLEAN_PATHS
├── install.sh     # 安装钩子（用 safe_link / pkg_install / log_* 等）
├── uninstall.sh   # 卸载钩子（用 unlink_safe）
└── files/         # 会被软链到 $HOME 的配置
```

新增模块的完整说明见 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 核心保证（都在 `lib.sh`）

- **备份而非覆盖**：`safe_link` 会先把目标处的真实文件移到 `~/.dotfiles_backup/<时间戳>/`。
- **幂等**：重复安装对已正确的软链是 no-op。
- **可逆**：`unlink_safe`（即 `envup uninstall`）只删指向仓库内部的软链，绝不动你自己的文件。
- **跨平台**：自动识别平台与包管理器。
- **网络超时**：`net_run` 给 git/curl 套 `timeout`，避免卡死。
- **dry-run**：`ENVUP_DRY_RUN=1` / `--dry-run` 预览所有改动。

## 文档

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) —— 架构与关键保证
- [docs/TMUX.md](docs/TMUX.md) —— tmux 速查
- [CONTRIBUTING.md](CONTRIBUTING.md) —— 新增模块 / 代码风格 / 测试

## 许可证

MIT —— 见 [LICENSE](LICENSE)

---

> 本文档与英文 [README.md](README.md) 对应；如有出入以英文版为准。
