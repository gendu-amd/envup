# envup

[![CI](https://github.com/gendu-amd/envup/actions/workflows/ci.yml/badge.svg)](https://github.com/gendu-amd/envup/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-yellow.svg)](LICENSE)

[English](README.md) | **简体中文**

envup 在 macOS、Linux、WSL2 和 Docker 恢复熟悉的终端开发环境。
一个 CLI 管理独立的 shell、Git、tmux、编辑器和搜索工具模块。
已有配置先备份；个人身份、历史、会话和项目工具链仍由你管理。

## 环境要求

- Bash 4.0+、Git 2.0+。macOS 先运行 `brew install bash`，envup 自动使用它。
- 配置和安装目录可写。

Root 和网络不是必需条件，但可用 provider 决定能安装哪些工具。
配置已链接不代表工作流已经完整可用。

## 快速开始

```bash
git clone --recursive https://github.com/gendu-amd/envup.git
cd envup
./envup install --dry-run       # 预览默认 standard 组合
./envup install
./envup status
./envup doctor
exec zsh                       # zsh 可用后加载配置
```

克隆时未带子模块，先运行 `git submodule update --init --recursive`。
仓库内用 `./envup`；安装 zsh 模块后也可直接用 `envup`。
zsh 模块配置 Oh-My-Zsh、Powerlevel10k、Vi 模式及 Bash 转入 zsh 的接入块，
有权限时还会修改登录 shell。保留其它 shell 时单独安装工具，自行接通 PATH 和集成。

## 选择工具

| Profile | 内容 |
|---|---|
| `minimal` | zsh、git |
| `standard`（默认） | minimal + 终端、搜索与 CLI 工具 |
| `full` | standard + nvim、lazygit、yazi |

```bash
./envup install --profile full
./envup install nvim tmux       # 只选指定模块
```

同时指定 profile 和模块时安装两者的并集。[完整模块列表](docs/guide.md#profiles-and-modules)。

## 日常入口

| 任务 | 命令或按键 |
|---|---|
| 接回 tmux / 选择项目 | `tm` / `ts` |
| 搜索文字 / 文件 / 历史 | `rg` / `Ctrl-t` / `Ctrl-r` |
| 跳转目录 | `z name` / `zi` |
| 编辑 / 查看 Git 改动 | `nvim file` / `lg` |
| 切换 tmux pane 与 Nvim split | `Ctrl-h/j/k/l` |
| 离开 tmux，保留运行任务 | `Ctrl-a`，再按 `d` |

对应工具可用时启用这些入口。
[全部快捷键](docs/guide.md#daily-shortcuts) · [Nvim](docs/guide.md#nvim)。

## 私有配置

| 文件 | 内容 |
|---|---|
| `~/.gitconfig.local` | Git 姓名、邮箱和个人覆盖 |
| `~/.zshrc.local` | Shell 设置与 PATH |
| `~/.tmux.local` | tmux 覆盖 |
| `~/.config/nvim/local.lua` | 编辑器覆盖 |
| `~/.config/nvim/envup.json` | 插件与语言选择 |

设置 `XDG_CONFIG_HOME` 时 Nvim 使用该目录。
例如 `{"languages":["c","cpp"]}` 选择 C/C++ 支持；省略选择则保留默认完整语言集。
修改后重启 Nvim 并运行 `envup install nvim`。
个人设置放私有文件；编辑共享软链会修改当前 checkout。
[配置与文件归属](docs/guide.md#configuration-model)。

## 检查与维护

```bash
envup status                   # 当前能力及上次安装结果
envup doctor --module nvim
envup doctor --fix              # 修复托管部分，再检查
envup upgrade --tools reuse     # 更新 checkout 和已登记模块
```

检查 degraded、skipped 和失败原因。导航和剪贴板要在实际项目、终端中验收，
安装成功不能替代功能检查。完整 `doctor --fix` 可能下载缺失的子模块。
Nvim 组件恢复用 `envup install nvim`；`clean nvim` 保留插件和语言工具。

卸载只撤销拥有的接入，保留用户数据、复用工具和备份。
Clean 只清声明的可丢弃缓存，两者都不自动恢复旧配置。
Checkout、系统包、安装器和插件变更各有恢复边界。

## 完整参考

详细参考集中维护在英文手册：

- [使用手册](docs/guide.md)：命令、模块、编辑器、配置和排障。
- [环境变量](docs/guide.md#environment-variables)。
- [Host Nvim 与 Docker 编译](docs/guide.md#docker-builds-with-host-side-nvim)。
- [验收与平台边界](docs/guide.md#functional-and-platform-acceptance)。
- [贡献指南](CONTRIBUTING.md)：架构、模块契约、检查和发布。
- [变更记录](CHANGELOG.md)：本 checkout 的变化，未发布工作保留在 `main`。

MIT，见 [LICENSE](LICENSE)。
