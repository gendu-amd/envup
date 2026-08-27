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

## 跑起来是什么样

一台你只有账号、别的什么都没有的服务器：

```console
$ ./envup install --profile standard
[i] install order: zsh git tmux fzf ripgrep fd bat eza zoxide atuin delta direnv
==> [zsh] install
✓ linked: ~/.zshrc
...
==> [zoxide] install
[i] [zoxide] release v0.9.6: zoxide-x86_64-unknown-linux-musl.tar.gz
✓ [zoxide] zoxide v0.9.6 installed to ~/.local/bin

✓ ok:       zsh git fzf ripgrep fd bat eza zoxide atuin delta direnv
⚠ degraded: tmux (usable but incomplete — see above)

$ ./envup status
[i] Platform: linux (x86_64)  PkgMgr: apt  Priv: none
Modules:
  ✓ zsh      Modern shell with Oh-My-Zsh + Powerlevel10k theme
  ✓ git      Git config (~/.gitconfig with delta as pager)
  ~ tmux     Terminal multiplexer with TPM + session restore  — tmux not found
  ○ nvim     Neovim editor with NvChad config + lazy.nvim plugins
  ✓ ok   ~ degraded (config linked, tool missing)   ! broken   ○ not installed

$ ./envup doctor
==> environment
[i] os=linux distro=ubuntu-24.04 arch=x86_64 libc=glibc-2.39 priv=none pkg=apt net=direct
==> modules
✓ [zsh] ok (5.9)
⚠ [tmux] degraded: tmux not found
  → the config is linked — it starts working the moment the tool exists
✓ doctor: this machine is healthy (1 note(s) above)

$ ./envup status --json | jq '.modules[] | select(.state != "absent") | {name, state, provider}'
{ "name": "zoxide", "state": "ok", "provider": "github_release" }
```

注意 `tmux` 那行：没有 root、也没有静态发布可下，所以工具本身没装上 —— 但配置已经链好了，整轮安装的退出码是 0。这是设计出来的结果，不是失败。

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
- `status` 反映**磁盘上此刻的真实状态**：重新读每一条软链、重新跑每一次版本检查。`✓ ok` / `~ degraded` / `! 需要处理` / `○ 未安装`。手删了配置，下次 status 就是 `!`。
- `!` 会说清是三种里的哪一种，因为处理方式不同：**`N links not created yet`**（repo 在你上次安装之后新增了软链，跑 `envup install <模块>` 即可，什么都没坏）、**`N dangling links`**（源文件或整个 checkout 被移动了，用 `envup doctor --fix`）、**`N paths already in use`**（你自己的文件正占着软链要去的位置，envup 只报告、不动你的文件）。
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

`github_release` 会按探测到的 OS / arch / libc 匹配 release 资产 —— 包括在 glibc 太旧的机器上自动选 **musl** 构建 —— 并用 [`versions.lock`](versions.lock) 钉版本，保证多机一致。凡是能走这条路的模块都在里面有一行，相隔几个月装起来的两台服务器也拿到同一个二进制；要换版本得改文件、提一次 commit，不会某天自己变了。

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

加一个新工具 = 新建一个目录，没有注册表要改、没有配置要同步。完整说明见
[CONTRIBUTING.md](CONTRIBUTING.md)。

| 模块 | 工具 | 依赖 |
|---|---|---|
| `zsh` | Oh-My-Zsh + Powerlevel10k 的现代 shell（同时把 zsh 设成你的默认 shell）| — |
| `git` | git 配置（有 delta 时用它做 pager）| — |
| `delta` | 带语法高亮的 git diff，装好即接到 git 上 | `git` |
| `tmux` | 终端复用（新 pane 用 zsh、`prefix f` 切项目、OSC 52 剪贴板、重启后恢复现场）| — |
| `fzf` | 模糊查找（Ctrl+T / Ctrl+R）| — |
| `ripgrep` | 快速递归搜索（`rg`），也是 Telescope 的后端 | — |
| `fd` | 更好用的 `find`，也是 fzf 列文件用的 | — |
| `bat` | 带高亮的 `cat`，`cat` 和 fzf 预览都走它 | — |
| `eza` | 现代 `ls` —— `ls`/`ll`/`la`/`tree` 都变成它 | — |
| `direnv` | 按目录的环境变量，`cd` 时从 `.envrc` 载入 | `zsh` |
| `zoxide` | 更聪明的 `cd` —— `z <目录>` 直接跳，`zi` 交互选 | `zsh` |
| `atuin` | SQLite 存储的 shell 历史 | `zsh` |
| `nvim` | Neovim + NvChad（插件版本由 lazy-lock.json 钉住）| — |

### 在远端机器上干活

tmux 模块里有三件事只在 SSH 场景下才有意义：

**重启不会让你丢掉现场。** 你正在用的那套布局 —— 窗口、pane、各自的目录、回滚缓冲、nvim 里开着的文件 —— 每 5 分钟存一次；重新登录后敲一个 `tm`（全名 `tmux-resume`）就回到那个状态。**这个命令存在是因为直接敲 `tmux` 是错的**：拉起 server 才会触发恢复，但恢复是异步的（要先 sleep 1 秒等插件加载完），而你的 `tmux` 已经立刻建好了一个空 session —— 你会停在一个空壳里，真正的布局一秒后出现在旁边，屏幕上没有任何提示。`tm` 会拉起 server、等恢复落地、再 attach 到回来的那些 session 上。**登录时不会自动帮你 attach**：自动路径必须替你猜"这条连接要不要 multiplexer"，猜错的结果就是把你丢进一个不是你原来那个的 session。存档按机器分开，所以 NFS 共用 home 时不会在 GPU 机器上给你恢复出编译机的布局。见 [docs/TMUX.md](docs/TMUX.md)。

**复制的东西落到你自己的电脑上。** 在 nvim 里 yank、或在 tmux 里复制，文字会经由你已经建好的那条 SSH 连接，进到你面前这台机器的剪贴板 —— 不需要 X11 转发、不需要 root、不需要额外的守护进程。但它需要你**本地终端**上的一个开关，这个 envup 管不到：见 [docs/CLIPBOARD.md](docs/CLIPBOARD.md)。（VS Code 和 Cursor 默认是关的。）

**`prefix f` 切项目。** fzf 列出你的项目目录，选中后连上（或新建）一个以项目命名的 tmux session —— 所以选一个已经开着的项目是回到它，而不是再开一份。tmux ≥ 3.2 会在当前 pane 上开一个 popup，更老的版本退回临时窗口 —— 按键时自己问，不用配。shell 里也可以用 `ts`。默认扫 `~/work/*`、`~/src/*`、`~/projects/*`、`~/dev/*`、`~/repos/*`、`~/go/src/*/*`，要改就在 `~/.config/envup/project-dirs` 里一行一个写自己的。见 [docs/TMUX.md](docs/TMUX.md)。

### 默认 shell

`zsh` 模块从三个方向保证你真的落在 zsh 里：

1. `chsh` 改登录 shell（下次登录生效）。
2. `chsh` 被禁的账号上（LDAP/SSSD 管理的公司/HPC 机器），往 `~/.bashrc` 里加一小段
   带守卫的代码，交互式 bash 会 `exec` 进 zsh。逃生口：`NO_ZSH=1 bash`。
3. `tmux` 模块把 `default-shell` 指向 zsh，所以不管系统登录 shell 是什么，新 pane
   都是 zsh。（是 `default-shell` 不是 `default-command`：前者 tmux 会当**登录
   shell** 跑，这样 `module load`、conda、macOS 的 `path_helper` 在"不是你的终端
   拉起来的" pane 里才还有效。）

`envup uninstall zsh` 会删掉 `~/.bashrc` 里那段（`chsh` 的设置不动）。如果这个
`~/.bashrc` 本来就是 envup 建的 —— 一个原本没有它的 home —— 而且删完就空了，文件
本身也一并收回。你原本就有的、或者你后来往里写过东西的，留着。

### nvim 模块

`nvim` 模块把 NvChad 配置链到 `~/.config/nvim` 并装插件。NvChad 需要
**nvim >= 0.10**，而发行版自带的往往更老 —— Debian stable 和 RHEL 都是。envup 自己
处理：引擎发现版本不够，就继续往下走 provider 链，改装官方 release 到
`~/.local/bin`。envup 从不动你的系统软件源。

连这条路也走不通时（没网、架构冷门），模块降级并打印你的选项：

```bash
brew install neovim                          # macOS
conda install -c conda-forge neovim          # 老 glibc 系统（RHEL/CentOS 8 …）
# 或从源码构建：https://github.com/neovim/neovim/blob/master/BUILD.md
```

**插件是可复现的。** 插件集由提交进仓库的 `lazy-lock.json` 钉住，并验证过在
nvim 0.10（老 glibc 机器）和 0.11（容器）上都能加载。`envup install nvim` 是**还原**
到锁文件里的那些版本，所以每台机器拿到的是同一个编辑器。用 `ENVUP_NVIM_LAZY` 控制：

- `restore`（默认）—— 按 `lazy-lock.json` 装钉住的版本。
- `sync` —— 在版本约束内更新到最新**并重写锁文件**；之后把新的 `lazy-lock.json`
  提交上去，就能推给所有机器。
- `skip` —— 留给 nvim 第一次交互启动时自己装。

`./envup clean nvim` 清掉插件/缓存状态，下次安装会从锁文件还原。

**在服务器上编辑。** 三个默认值是照着服务器的真实用法选的，都可以调：

- undo 跨会话保留（`undofile`）。掉线会一起杀掉 shell 和 nvim，没有这个的话上次
  保存之后的东西全没。
- 超过 1.5 MB 的缓冲区打开时关掉语法高亮、treesitter、LSP、折叠、undo 和 swap，
  并告诉你它这么做了。tail 一个 200 MB 的日志不再等于终端被杀。
  `vim.g.envup_bigfile_bytes = 0` 关掉这个行为。
- 保存时格式化**只在项目自带风格配置时**才跑（`.clang-format`、`stylua.toml`、
  `pyproject.toml` …），因为没有 `.clang-format` 的 clang-format 会把整个文件重排成
  LLVM 风格 —— 在别人的仓库里，那个 diff 得你自己解释。`<leader>fm` 随时手动格式化；
  `vim.g.envup_format_always = true` 让它无条件跑。

## 它是怎么工作的

```
┌───────────────────────────────────────────────────────────────┐
│  ./envup install --profile standard                           │
│         ↓                                                     │
│  探测能力：OS、发行版、arch、libc、权限、网络                 │
│         ↓                                                     │
│  载入 profiles/standard.sh → MODULES=(zsh git ...)            │
│         ↓                                                     │
│  按 DEPENDS 解析安装顺序                                      │
│         ↓                                                     │
│  对每个模块，引擎：                                           │
│    读 meta.sh（纯数据）                                       │
│    按探测到的能力，沿 PROVIDERS 走到第一个可行的             │
│    把 LINKS 软链进 ~/（已有真实文件先备份）                   │
│    跑 hooks.sh 里的 post_install（如果有）                    │
│    验证 VERIFY_BIN / VERIFY_MIN_VERSION                       │
│    把 名字+状态+provider+版本 记进 manifest                   │
│         ↓                                                     │
│  逐模块给出 ok / degraded / skipped / failed 和原因           │
│         ↓                                                     │
│  日志写到 ~/.local/state/envup/logs/install_<时间戳>.log      │
└───────────────────────────────────────────────────────────────┘
```

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

## 环境变量

全部可选，默认值适用于常见情况。安装时读取。

| 变量 | 默认 | 作用 |
|---|---|---|
| `ENVUP_DRY_RUN` | `0` | 为 `1` 时每个有破坏性的步骤只打印会做什么，不真做。`--dry-run` 会自动设上。 |
| `ENVUP_OFFLINE` | `0` | 为 `1` 时完全不尝试联网：下载步骤立刻放弃而不是等超时，配置照常落地。 |
| `ENVUP_GH_MIRROR` | — | GitHub 流量走的镜像前缀，如 `https://ghproxy.com`。release、clone、raw 文件都算。只改写 GitHub 自己的域名，厂商自有安装地址原样放行。 |
| `ENVUP_REQUIRE_CHECKSUM` | `0` | 为 `1` 时，对不上已发布摘要的二进制拒装而不是照装。默认关，因为 fd、bat、delta 等上游根本不发摘要。配合 `ENVUP_GH_MIRROR` 时值得开。 |
| `ENVUP_LOCAL_BIN` | `~/.local/bin` | 免 root 安装时二进制的落点。 |
| `ENVUP_LOCAL_OPT` | `~/.local/opt` | 整棵目录树而非单个文件的 release（nvim、fzf）解包到这里，里面的二进制再链到 `ENVUP_LOCAL_BIN`，所以 `PATH` 上只需要那一个目录。 |
| `ENVUP_BACKUP_DIR` | `~/.dotfiles_backup/<时间戳>` | 链接目标处**已有真实文件**时，先搬到这里再建链。每轮一个目录，里面保留原来的相对路径，既不撞名也看得出文件原来在哪。 |
| `ENVUP_STATE_DIR` | `~/.local/state/envup` | manifest、日志、adopt 暂存。认 `XDG_STATE_HOME`，但只在这台机器还没在用默认路径时才认。 |
| `ENVUP_LOG_DIR` | `$ENVUP_STATE_DIR/logs` | 日志文件目录。 |
| `ENVUP_LOG_FILE` | `ENVUP_LOG_DIR` 下的带时间戳文件 | 指定这一轮日志写到哪；设成 `/dev/null` 就不留日志。一般不用动，每条命令会自己开一个。 |
| `ENVUP_LOG_LEVEL` | `info` | `debug`/`info`/`warn`/`error`，控制终端详略。日志文件始终记录全量。 |
| `ENVUP_MODULE_TIMEOUT` | `900` | 每个模块钩子外层的看门狗。卡住的模块会被杀掉并记为失败，整轮继续。 |
| `ENVUP_NET_TIMEOUT` | `120` | git 操作的单命令超时。`timeout(1)` 不可用时优雅退化（macOS 装 coreutils 可得 `gtimeout`）。 |
| `ENVUP_NET_TIMEOUT_NVIM` | `600` | `nvim --headless +Lazy!` 的超时——clone 三十多个插件要几分钟。 |
| `ENVUP_NET_TIMEOUT_INSTALLER` | `300` | `curl ... \| sh` 类安装脚本的超时。 |
| `ENVUP_NET_KILL_AFTER` | `10` | 网络超时后到 SIGKILL 之间的宽限秒数，防止卡死的连接超出预算。 |
| `ENVUP_NET_PROBE_TIMEOUT` | `5` | 判定 `direct`/`mirror`/`offline` 那次探测的等待时间。这是**探测**不是下载——该调大的是"半天不应答"的链路，不是"传得慢"的链路。 |
| `ENVUP_PRIV_KEEP_ENV` | 自动探测 | 提权命令是否走 `sudo -E`。设了代理时 envup 会探测 `sudo -n -E true` 并按结果决定；`1` 强制开，`0` 强制关。sudoers 规则让探测结果失真的机器上值得手动设——关掉且有代理时，`apt-get` 没有出网路径，只会超时死掉。 |
| `ENVUP_EDITOR` | — | shell 挑 `EDITOR` 时优先尝试的编辑器，排在 `nvim`/`vim`/`vi`/`nano` 之前。这台机器上没装就继续往下找，所以同一个值在所有机器上设都是安全的。 |
| `ENVUP_PLATFORM` | 自动探测 | 强制平台判定：`macos`/`linux`/`wsl2`/`docker`。探测本身是可靠的，这个变量是为了复现另一台机器的行为。 |
| `ENVUP_NVIM_LAZY` | `restore` | `restore` 按 `lazy-lock.json` 装钉住的版本；`sync` 更新到最新并重写锁文件；`skip` 留给 nvim 首次启动。 |
| `ENVUP_ATUIN_INSTALL` | — | 设成 `skip` 跳过 atuin 模块（它的安装器被网络/代理挡住时好用）。 |
| `ENVUP_ZSH_QUIET` | `0` | shell 侧：为 `1` 时配置切片加载失败静默处理。默认会打印是哪个切片、为什么。 |

Docker 里试一下：

```bash
docker run -it --rm ubuntu:24.04 bash -c '
    apt-get update && apt-get install -y git ca-certificates &&
    git clone --recursive https://github.com/gendu-amd/envup.git /opt/envup &&
    /opt/envup/envup install --profile standard
'
```

### 你原本就有的 dotfiles

如果软链目标处已经是一个**真实文件**（比如你自己手写的 `~/.zshrc`），envup **一定会
先备份**到 `~/.dotfiles_backup/<时间戳>/` 再建链 —— 绝不静默覆盖。备份里保留原来的
相对路径（`~/.config/nvim` 存成 `<备份>/.config/nvim`），所以要恢复就是 `mv` 回对应
位置，而且 `$HOME` 之外的东西不会和里面的撞名。

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

## 日志与排查

```bash
./envup log              # 最近一次会改动机器的命令的日志
./envup log --tail       # 实时跟（长安装时有用）

# 日志留在：
ls ~/.local/state/envup/logs/     # 改过 $ENVUP_STATE_DIR 的话在那底下
```

**先跑 `envup doctor`。** 它体检这台机器、点名哪里不对，`--fix` 能修掉大部分：

```bash
./envup doctor          # 这台机器上什么坏了？
./envup doctor --fix    # 修，然后重查一遍再给结论
```

还是不行的话：
1. 看日志 —— 每条命令的退出码、耗时、stderr 都记着。
2. 用 `--dry-run` 重跑，看它打算做什么。
3. `ENVUP_LOG_LEVEL=debug` 会打印 provider 的决策过程（为什么走这条路不走那条）。
4. 模块就在 `modules/<name>/` —— `meta.sh` 是数据，`hooks.sh` 是自定义步骤。

### 常见问题

**模块回来是 `degraded`** —— 这是报告不是失败：配置已链好，只是工具本身在这台机器上
装不了（通常是没 root 又没有静态发布可退）。`envup doctor` 会点名是哪个工具。等谁把
包装上就自动生效，不用重装。

**zsh 提示符很朴素 / Powerlevel10k 没了** —— 多半是 clone 时忘了 `--recursive`。
`envup doctor` 会明确报出来，修法：

```bash
git submodule update --init --recursive   # 或者：./envup doctor --fix
./envup install zsh
```

**`setlocale: cannot change locale`** —— envup 0.2 起不再硬设 locale：它从
`en_US.UTF-8` / `C.UTF-8` 里挑这台机器真有的那个，只设 `LANG`，永不设 `LC_ALL`。
还看得到这个警告，说明是你环境里别的东西设的 —— 两种情况 `envup doctor` 都会报。

**装完 `envup: command not found`** —— `zsh` 模块会把 `envup` 链到
`~/.local/bin/envup`，确认 `~/.local/bin` 在 `$PATH` 上（重新登录，或 `exec zsh`）。
没在的话 `envup doctor` 会提醒。

**把仓库挪了个位置，全崩了** —— 所有软链都指着旧路径。envup 记录了建链时仓库在哪，
所以这会是一条消息而不是二十条：`envup doctor --fix` 从新位置重建。

**`envup upgrade` 更新不动源码** —— 它会告诉你是哪一种，而不是只丢一句 git 的原话。
托管配置被顺着 `~/.zshrc` 软链改了 → 逐个文件列出，用 `envup adopt` 把追加的内容移
出去（见[配置同步](#配置同步)）。其它未提交改动 → 列出来，给 `git stash`。HEAD 游离
（之前 `upgrade --ref v0.2.0` 留下的）→ 在联网之前就拦下，并给出
`envup upgrade --ref main` 这条回去的路。分支没有 upstream、或者压根不是 git 检出 →
如实说明。

**`nvim too old`** —— NvChad 需要 nvim >= 0.10，而 envup 不动你的系统软件源。用
`brew install neovim`、`conda install -c conda-forge neovim`（老 glibc 系统如
RHEL/CentOS 8 上最好用）或源码构建，然后重跑 `envup install nvim`。

**nvim 的 Lazy 插件坏了 / 想要个干净状态** —— `./envup clean nvim` 清掉插件缓存和
Mason 装的 LSP，不碰你的配置；下次 `./envup install nvim` 从 `lazy-lock.json` 还原
到钉住的那套。

**网络慢或被墙，`install` / `upgrade` 一直挂着** —— 每个联网操作（git pull、clone、
子模块更新、nvim Lazy）都套了单命令超时（git 默认 120s，Lazy 600s）。撞上会看到
`TIMED OUT after Ns` 和调大 `ENVUP_NET_TIMEOUT=...` / `ENVUP_NET_TIMEOUT_NVIM=...`
的提示。代理/VPN 慢的话：`ENVUP_NET_TIMEOUT=300 ./envup upgrade`。

**macOS 上的 timeout 警告** —— 日志里的 `no 'timeout' command on this system` 意思是
这次安装没有超时保护。装 GNU coreutils：`brew install coreutils` 提供 `gtimeout`，
envup 会自动识别。

## 支持的平台

| 平台 | 测试情况 |
|---|---|
| macOS（Apple Silicon / Intel）| ✓ |
| Ubuntu / Debian | ✓ |
| Fedora / CentOS | ✓（尽力而为）|
| Arch Linux | ✓（尽力而为）|
| Alpine | 尽力而为 |
| WSL2 | ✓ |
| Docker | ✓ |

bash 的下限是 **4.0**，并且 CI 真的在 `centos:7`（bash 4.2）上跑 —— 不只是文档里
写写。这个下限覆盖 RHEL/CentOS 7 和 Ubuntu 16.04。

## 文档

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) —— 架构与关键保证
- [docs/TMUX.md](docs/TMUX.md) —— tmux 速查、项目切换器、按机器分层的配置
- [docs/CLIPBOARD.md](docs/CLIPBOARD.md) —— 用 OSC 52 把服务器上复制的东西送回本机
- [CONTRIBUTING.md](CONTRIBUTING.md) —— 新增模块 / 代码风格 / 测试
- [CHANGELOG.md](CHANGELOG.md) —— 版本变更与迁移说明
- [docs/history/](docs/history/) —— 已冻结的历史文档（v0.1 那轮重构的计划与结项），
  记的是当时为什么那样判断，不是当前架构

## 许可证

MIT —— 见 [LICENSE](LICENSE)

---

> 本文档与英文 [README.md](README.md) 对应；如有出入以英文版为准。
