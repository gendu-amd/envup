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

# 安装 standard profile（zsh, git, tmux, fzf, ripgrep, fd, bat, eza,
# zoxide, atuin, delta, direnv）
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
- **`upgrade` 更新不动源码时，会说清楚是撞上了 envup 自己的哪种失败**：托管配置被人顺着软链改了（逐个文件列出，给 `envup adopt`）、其它未提交改动（给 `git stash`）、之前 `--ref` 留下的游离 HEAD（在联网之前就拦下，并给出回去的命令）、分支没有 upstream、或者这压根不是一个 git 检出。插件子模块停在更新的 commit 上属于正常状态，不会被当成脏。
- `upgrade --keep-going` 即使更新失败也继续重装；默认则中止，免得悄悄拿旧源码重装一遍。
- `upgrade --dry-run` 完全不碰检出，只预览。
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
ENVUP_REQUIRE_CHECKSUM=1 ./envup install               # 校验不了的二进制就不装
```

下载下来的 release 二进制会和同一个 release 里发布的摘要（`checksums.txt`、`<资产名>.sha256` 之类）比对。这防不住上游被入侵——摘要和文件走的是同一条链路——但它拦得住真正常见的那类事故：代理返回 200 加一个登录页、连接中断留下半个文件、镜像慢了一周还在发上个版本。这三种现在都能装得干干净净，然后在别的地方出问题。

不少上游（fd、bat、delta）压根不发摘要，所以"没得校验"默认只记一条 debug 日志，照装。`ENVUP_REQUIRE_CHECKSUM=1` 把它变成拒绝——`ENVUP_GH_MIRROR` 指向一个不是你自己运维的代理时，值得开。

envup 所有出网都收敛在一处（`lib/net.sh`），所以这些变量覆盖全部场景 —— release 下载、clone、厂商安装脚本都算。模块里出现裸 `curl` 是 lint 错误，就是为了保证这一点，`envup doctor --authoring` 会拦。

`ENVUP_GH_MIRROR` 只改写 GitHub 自己的域名（github.com、raw/api/objects/codeload.githubusercontent.com）。厂商自有的安装地址（比如 atuin 的 `https://setup.atuin.sh`）原样放行 —— GitHub 代理服务不了它没听说过的域名，硬加前缀只会在最需要镜像的那批机器上 404。这类地址如果也进不去，用 `http_proxy` / `https_proxy`。

`https_proxy` / `http_proxy` 在提权时会被保留（设了代理就用 `sudo -E`）—— 这是公司代理下 `apt-get install` 能成功的前提。

git **子模块**用 git 自己的重定向：
`git config --global url."https://ghproxy.com/https://github.com/".insteadOf https://github.com/`。

### 多机共用一个 home

NFS/autofs 集群上很常见。由此引出两件事，envup 都处理了：

- 软链归属判断同时比对**解析态和未解析态**路径，所以 `/home` → `/mnt/home` 这种自动挂载不会让 envup 拒绝删除自己创建的链接。
- 每台机器专属的配置放在各模块的 `hosts/<hostname>` 文件里（纳入版本管理、能同步、按机器天然隔离），而不是一个共享的 "local" 文件。zsh、tmux、nvim、git 都有这一层，见下文[配置同步](#配置同步)。

## Profiles

| Profile | 模块 | 场景 |
|---------|------|------|
| `minimal` | `zsh git` | 裸服务器、无头容器 |
| `standard`（默认） | `+ tmux fzf ripgrep fd bat eza zoxide atuin delta direnv` | 典型开发机 |
| `full` | `+ nvim` | 高级工作站 |

Profile 通过 `use_profile` **组合**，每层只写自己新增的部分：

```bash
# profiles/standard.sh = minimal + 终端工具
use_profile minimal
MODULES+=(tmux fzf ripgrep fd bat eza zoxide atuin delta direnv)

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

### 在远端机器上干活

tmux 模块里有三件事只在 SSH 场景下才有意义：

**重启不会让你丢掉现场。** 你正在用的那套布局 —— 窗口、pane、各自的目录、回滚缓冲、nvim 里开着的文件 —— 每 5 分钟存一次，重新登录就直接回到那个状态。不用敲任何东西：登录 shell 会拉起 tmux server，等恢复跑完，然后 attach。存档按机器分开，所以 NFS 共用 home 时不会在 GPU 机器上给你恢复出编译机的布局。想要一个干净 shell 就 `NO_TMUX=1 ssh box`。见 [docs/TMUX.md](docs/TMUX.md)。

**复制的东西落到你自己的电脑上。** 在 nvim 里 yank、或在 tmux 里复制，文字会经由你已经建好的那条 SSH 连接，进到你面前这台机器的剪贴板 —— 不需要 X11 转发、不需要 root、不需要额外的守护进程。但它需要你**本地终端**上的一个开关，这个 envup 管不到：见 [docs/CLIPBOARD.md](docs/CLIPBOARD.md)。（VS Code 和 Cursor 默认是关的。）

**`prefix f` 切项目。** fzf 列出你的项目目录，选中后连上（或新建）一个以项目命名的 tmux session —— 所以选一个已经开着的项目是回到它，而不是再开一份。tmux ≥ 3.2 会在当前 pane 上开一个 popup，更老的版本退回临时窗口 —— 按键时自己问，不用配。shell 里也可以用 `ts`。默认扫 `~/work/*`、`~/src/*`、`~/projects/*`、`~/dev/*`、`~/repos/*`、`~/go/src/*/*`，要改就在 `~/.config/envup/project-dirs` 里一行一个写自己的。见 [docs/TMUX.md](docs/TMUX.md)。

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

tmux、nvim、git 有同样的两层，各自带一份模板可以直接抄：

| 模块 | 提交进仓库、按机器区分 | 私有、优先级最高 |
|---|---|---|
| zsh | `modules/zsh/files/.zshrc.d/hosts/<host>.zsh` | `~/.zshrc.local` |
| tmux | `modules/tmux/files/hosts/<host>.conf` | `~/.tmux.local` |
| nvim | `modules/nvim/files/hosts/<host>.lua` | `~/.config/nvim/local.lua` |
| git | `modules/git/files/hosts/<host>.gitconfig` | `~/.gitconfig.local` |

```bash
cp modules/tmux/files/hosts/example.conf.template \
   modules/tmux/files/hosts/$(hostname -s).conf
envup install tmux          # 建链
```

tmux 的 `source-file` 和 git 的 `[include]` 都不会展开 hostname，所以由 envup 在安装时把名字解析出来、链到一个固定路径（`~/.tmux/host.conf`、`~/.gitconfig.host`）。因此**新建**一个 host 文件需要跑一次 `envup install <模块>`；改已有的不用。zsh 和 nvim 自己读 hostname，两种情况都不用。

git 在这两层之下还有一层 `~/.gitconfig.envup`：每次安装按这台机器上真实存在的东西重写 —— 有 delta 就在这里启用它做 pager，没有就什么都不写。提交进仓库的 `.gitconfig` 里不出现任何二进制名字，所以缺工具的机器上 `git diff` 不会坏掉。

### 万一还是有东西写进了仓库

因为 `~/.zshrc` 是指向仓库的软链，某个"贴心"的第三方安装脚本往它尾部追加，就是在改一个被跟踪的文件 —— 下一台机器上 `envup upgrade` 的 `git pull` 就会失败。（失败时 envup 会直接点名是哪几个文件、并提示 `envup adopt`，不会只丢一句 git 的原话给你。）

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

- **备份而非覆盖**：`safe_link` 会先把目标处的真实文件移到 `~/.dotfiles_backup/<时间戳>/`，并且**保留原来的相对路径**（`~/.config/git/ignore` 存成 `<备份>/.config/git/ignore`）。这样既能从备份本身看出文件原来在哪，两个同名文件也不会互相覆盖。
- **幂等**：重复安装对已正确的软链是 no-op。
- **可逆**：`unlink_safe`（即 `envup uninstall`）只删指向仓库内部的软链，绝不动你自己的文件。另外两样不是软链、但确实是 envup 造出来的东西也会一并收回：只为放一个软链而建的目录（仅在空目录时 `rmdir`），以及为了写 zsh shim 而不得不新建的 `~/.bashrc`（仅当"是 envup 建的"且"现在又空了"时才删）。你原本就有的 `~/.bashrc`、你后来往里写的内容、系统包、`~/.gitconfig.local` 都不动。
- **跨平台**：自动识别平台、包管理器、架构、libc、权限、网络。
- **卡不死**：网络与包管理器有超时，模块钩子有看门狗。
- **有日志**：任何会改动机器的命令都会在 `$ENVUP_STATE_DIR/logs/`（默认 `~/.local/state/envup/logs/`）留一份带时间戳的日志，`doctor`（尤其是 `--fix`）和 `adopt` 也在内。`ENVUP_STATE_DIR` 存放 manifest、日志和 adopt 的暂存，认 `XDG_STATE_HOME` —— 但只在这台机器还没在用默认路径时才认，免得你事后设了这个变量、一个装好的环境却显示成没装。
- **dry-run 是彻底的**：`ENVUP_DRY_RUN=1` / `--dry-run` 预览所有改动，provider 内部也一样。
- **可降级**：这台机器装不上的东西被如实报告而不是致命错误，配置无论如何都会落地。

## 从 0.1.x 升级

0.2.0 有 breaking change，完整列表和迁移步骤见 [CHANGELOG.md](CHANGELOG.md)。最可能影响到你的两条：

1. 个人覆盖从 `~/.zshrc.d/local.zsh` 换到了 `~/.zshrc.local`（旧文件仍会被加载并给出提示，不会丢）。
2. `envup doctor` 现在默认体检机器；原先的模块写法校验是 `envup doctor --authoring`。

## 文档

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) —— 架构与关键保证
- [docs/TMUX.md](docs/TMUX.md) —— tmux 速查、项目切换器、按机器分层的配置
- [docs/CLIPBOARD.md](docs/CLIPBOARD.md) —— 用 OSC 52 把服务器上复制的东西送回本机
- [CONTRIBUTING.md](CONTRIBUTING.md) —— 新增模块 / 代码风格 / 测试
- [CHANGELOG.md](CHANGELOG.md) —— 版本变更与迁移说明

## 许可证

MIT —— 见 [LICENSE](LICENSE)

---

> 本文档与英文 [README.md](README.md) 对应；如有出入以英文版为准。
