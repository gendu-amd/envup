# envup

> 一个仓库、一个 CLI、一条命令 —— 跨平台的开发环境。

[![CI](https://github.com/gendu-amd/envup/actions/workflows/ci.yml/badge.svg)](https://github.com/gendu-amd/envup/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
![Platforms](https://img.shields.io/badge/platform-macOS%20%7C%20Linux%20%7C%20WSL2%20%7C%20Docker-blue)
![Shell](https://img.shields.io/badge/shell-bash%20%E2%89%A5%204-green)

[English](README.md) | **简体中文**

一个模块化的 dotfiles 管理器：用一条命令在任意新机器上装好你的 shell、编辑器与 CLI 工具。可以按 profile（minimal / standard / full）安装，也可以只装单个模块；不想要的随时卸载；全程有日志、可回滚。

它是为**你说了不算的机器**设计的：没有 root、有公司代理、home 目录被整个集群共享、macOS 和 Linux 混用。在这些机器上，结果要么是"装好了"，要么是一条明确的原因 —— 不会挂死，也不会留下一个配了一半的 shell。

## 环境要求

- **bash ≥ 4.0**（模块依赖解析用到关联数组）。**macOS** 的 `/bin/bash` 仍是 3.2 —— 先 `brew install bash` 一次；`./envup` 会自动识别 Homebrew 的 bash（登录 shell / tmux shell 仍可用 zsh）。
- **git ≥ 2.0**
- **POSIX 系统**：macOS、Linux（Ubuntu/Debian/Fedora/CentOS/Arch/Alpine）、WSL2 或 Docker

以下全部**可选**：

- **root / sudo** —— 没有就绕开系统包管理器，改把静态二进制装进 `~/.local/bin`。需要编译的工具（`zsh`/`git`/`tmux`）会标记为 **degraded**：配置照常落地，等管理员装上包立刻生效。全程不弹提示、不阻塞。
- **包管理器**（apt / dnf / yum / pacman / brew / apk）—— 有且可用时才用。
- **网络** —— 没有也能装：所有配置文件照常落地，下载步骤直接跳过（可用 `ENVUP_OFFLINE=1` 提前声明）。
- 建议把 `~/.local/bin` 加入 `$PATH`；`zsh` 模块会帮你加，`envup doctor` 会在没加时提醒。

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
./envup install [--profile NAME] [--dry-run] [MODULE...]      # 安装
./envup uninstall [--all] [--dry-run] MODULE...               # 卸载
./envup upgrade [--profile NAME] [--ref TAG] [--dry-run] ...  # 更新 + 重装
./envup status [--json]                                       # 每个模块的真实状态
./envup doctor [--fix] [--authoring] [--module NAME]          # 体检这台机器
./envup adopt [--dry-run] [PATH...]                           # 把第三方改动移出仓库
./envup clean [--dry-run] [--all | MODULE...]                 # 清理 meta 声明的缓存
./envup log [--tail]                                          # 最近一次命令的日志
./envup --version                                             # 打印版本
```

用 `./envup <command> --help` 查看各命令选项。几个不那么显然的语义：

- **安装结果有四态，不是两态**：`ok`（装好并验证通过）/ `degraded`（配置已落，工具没装上）/ `skipped`（这台机器不适用）/ `failed`（真的坏了）。只有 `failed` 才是非零退出 —— 受限服务器上的 degraded 是预期结果，脚本不该当成错误。**单个模块失败不会中断整轮安装。**
- `install --profile X MODULE...` 是**并集**，不是二选一。
- `upgrade` 默认只重装 manifest 里已有的模块；用 `--profile` 可纳入 profile 新增的模块。
- `upgrade --ref v0.2.0` 会切到指定 tag/分支（fetch + checkout + 子模块），用于**钉版本**。
- `status` 反映**磁盘上此刻的真实状态**：重新读每一条软链、重新跑每一次版本检查。`✓ ok` / `~ degraded` / `! broken` / `○ 未安装`。手删了配置，下次 status 就是 `!`。
- `doctor` 体检**这台机器**：软链、工具版本、manifest、子模块、`~/.local/bin` 是否在 PATH、locale 是否有效、仓库是否被移动或被污染。`--fix` 修完会**再查一遍**，所以干净退出的含义是"已修好"，而不是"我试过了"。
- `doctor --authoring` 是另一半：静态校验仓库里的模块写法（元数据字段、钩子是否 function 包裹、`DEPENDS` 是否存在、有没有裸下载、`CLEAN_PATHS` 是否误含用户数据）。新增模块后跑一下。
- `adopt` 处理"第三方安装脚本往你的托管配置里追加了几行"这种情况，见下文[配置同步](#配置同步)。
- **任何一步都卡不死整轮**：网络调用和包管理器都有超时，每个模块钩子还套了一层看门狗（`ENVUP_MODULE_TIMEOUT`，默认 900s）。
- `ENVUP_LOG_LEVEL=debug|info|warn|error`（默认 `info`）控制终端输出详略；日志文件始终记录全量。

## 你说了不算的机器

### 没有 root

envup 里没有任何一处会弹 `sudo` 密码提示。它用 `sudo -n true` 探测 —— 探不过就直接放弃系统包管理器，走别的路。（这个探测很关键：一个卡在等密码的 `sudo`，正是过去非交互安装要等 15 分钟才被看门狗杀掉的原因。）

每个模块声明一条有序回退链，引擎挑第一个在这台机器上可行的：

| Provider | 做什么 | 需要 root？ |
|---|---|---|
| `system` | apt / dnf / yum / pacman / brew / apk | 需要（brew 除外）|
| `github_release` | 下载匹配的预编译二进制到 `~/.local/bin` | 不需要 |
| `git` | clone 自带安装脚本的仓库（fzf）| 不需要 |
| `script` | 官方 `curl \| sh` 安装脚本 | 不需要 |
| `manual` | 打印手动指引，模块标记为 degraded | — |

`github_release` 会按探测到的 OS / arch / libc 匹配 release 资产 —— 包括在 glibc 太旧的机器上自动选 **musl** 构建 —— 并用 `versions.lock` 钉版本，保证多机一致。

`zsh`/`git`/`tmux` 需要编译且没有静态发布，无 root 时会是 `degraded`：**配置文件照样落地**，管理员装上包后立即生效，不需要重装。

### 代理、镜像、完全离线

```bash
ENVUP_GH_MIRROR=https://ghproxy.com ./envup install    # GitHub 走镜像
ENVUP_OFFLINE=1 ./envup install --profile minimal      # 根本不尝试，只落配置
```

envup 所有出网都收敛在一处（`lib/net.sh`），所以这两个变量覆盖全部场景 —— release 下载、clone、厂商安装脚本都算。模块里出现裸 `curl` 是 lint 错误，就是为了保证这一点，`envup doctor --authoring` 会拦。

`https_proxy` / `http_proxy` 在提权时会被保留（设了代理就用 `sudo -E`）—— 这是公司代理下 `apt-get install` 能成功的前提。

git **子模块**用 git 自己的重定向：
`git config --global url."https://ghproxy.com/https://github.com/".insteadOf https://github.com/`。

### 多机共用一个 home

NFS/autofs 集群上很常见。由此引出两件事，envup 都处理了：

- 软链归属判断同时比对**解析态和未解析态**路径，所以 `/home` → `/mnt/home` 这种自动挂载不会让 envup 拒绝删除自己创建的链接。
- 每台机器专属的 shell 配置放在 `~/.zshrc.d/hosts/<hostname>.zsh`（纳入版本管理、能同步、按机器天然隔离），而不是一个共享的 "local" 文件。见下文[配置同步](#配置同步)。

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
├── meta.sh        # 纯数据：装什么、怎么验证、链什么
├── hooks.sh       # 可选：pre/post_install 等函数
└── files/         # 会被软链到 $HOME 的配置
```

`meta.sh` 只**声明**、不执行 —— 引擎读它然后干活。一个模块常常十几行、一行逻辑都没有：

```bash
NAME="zoxide"
DESCRIPTION="Smarter cd — 'z <dir>' to jump, 'zi' to pick interactively"
DEPENDS=(zsh)

VERIFY_BIN="zoxide"                        # 引擎据此判断是否真的装好
PROVIDERS=(system github_release script)   # 有序回退链
GH_REPO="ajeetdsouza/zoxide"

LINKS=()
CLEAN_PATHS=()
```

新增模块的完整说明见 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 配置同步

配置是**软链**而非拷贝：改 `~/.zshrc` 实际改的是仓库里的 `modules/zsh/files/.zshrc`，`git pull` 到另一台机器立即生效，不需要重装。

### 每台机器不一样的设置

两层，区别在于"这台机器重装后你还想不想要它"：

```bash
# 纳入版本管理、会同步、按 hostname 区分 —— 代理、CUDA 路径、module load、时区、机器专属 alias
cp ~/.zshrc.d/hosts/example.zsh.template ~/.zshrc.d/hosts/$(hostname -s).zsh

# 永不提交、在仓库之外、最后加载所以优先级最高 —— token、一次性实验
$EDITOR ~/.zshrc.local                  # 这个 home 下所有机器
$EDITOR ~/.zshrc.local.$(hostname -s)   # 只这台机器
```

私有那层特意放在 `$HOME` 而**不是**仓库里。仓库里的 gitignore 文件是个陷阱：它同步不了，NFS 共享 home 上所有机器还共用同一份，而且任何往 `~/.zshrc` 写东西的工具都在往版本控制里写。

### 万一还是有东西写进了仓库

因为 `~/.zshrc` 是指向仓库的软链，某个"贴心"的第三方安装脚本往它尾部追加，就是在改一个被跟踪的文件 —— 下一台机器上 `envup upgrade` 的 `git pull` 就会失败。

`envup doctor` 会发现，`envup adopt` 负责还原：

```console
$ envup doctor
⚠ modules/zsh/files/.zshrc has lines appended after the last commit — a tool may have edited it
  → move them out of the repo: envup adopt modules/zsh/files/.zshrc

$ envup adopt
✓ modules/zsh/files/.zshrc: appended lines moved to ~/.zshrc.local, file restored
```

它只处理**纯追加**这一种形态；你自己改的内容会被报出来但原样保留。

## 核心保证

- **备份而非覆盖**：`safe_link` 会先把目标处的真实文件移到 `~/.dotfiles_backup/<时间戳>/`。
- **幂等**：重复安装对已正确的软链是 no-op。
- **可逆**：`unlink_safe`（即 `envup uninstall`）只删指向仓库内部的软链，绝不动你自己的文件。
- **跨平台**：自动识别平台、包管理器、架构、libc、权限、网络。
- **卡不死**：网络与包管理器有超时，模块钩子有看门狗。
- **dry-run 是彻底的**：`ENVUP_DRY_RUN=1` / `--dry-run` 预览所有改动，provider 内部也一样。
- **可降级**：这台机器装不上的东西被如实报告而不是致命错误，配置无论如何都会落地。

## 从 0.1.x 升级

0.2.0 有 breaking change，完整列表和迁移步骤见 [CHANGELOG.md](CHANGELOG.md)。最可能影响到你的两条：

1. 个人覆盖从 `~/.zshrc.d/local.zsh` 换到了 `~/.zshrc.local`（旧文件仍会被加载并给出提示，不会丢）。
2. `envup doctor` 现在默认体检机器；原先的模块写法校验是 `envup doctor --authoring`。

## 文档

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) —— 架构与关键保证
- [docs/TMUX.md](docs/TMUX.md) —— tmux 速查
- [CONTRIBUTING.md](CONTRIBUTING.md) —— 新增模块 / 代码风格 / 测试
- [CHANGELOG.md](CHANGELOG.md) —— 版本变更与迁移说明

## 许可证

MIT —— 见 [LICENSE](LICENSE)

---

> 本文档与英文 [README.md](README.md) 对应；如有出入以英文版为准。
