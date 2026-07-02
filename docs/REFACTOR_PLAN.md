# envup 重构优化计划书

> 配套文件：[`docs/REFACTOR_BASELINE.md`](./REFACTOR_BASELINE.md)（冻结的问题清单，最终对照用）。
> 分支：`refactor`；基线：git tag `baseline/pre-refactor`（提交 `a5263c4`）。
>
> **本文的定位**：不是"喊优化口号"，而是给出每个问题的**现状定位（精确到文件/函数/行）→ 根因 → 目标方案（含设计与代码骨架）→ 实施步骤 → 可执行的验收判据 → 风险**。先把调研做透（第 4 节），再动手（第 5 节），避免"永远在重复修 bug"。

---

## 目录

1. 背景
2. 目的与成功标准
3. 设计原则与约束
4. **前期调研 · 现状勘察**（关键不变量、问题再核实、网络入口清单、shellcheck 预勘）
5. 分阶段实施（每个工作项完整规格）
6. 分支与提交策略
7. 验收与对照机制
8. 风险与回滚
9. 工作项索引与进度总览

---

## 1. 背景

envup 是跨平台 dotfiles / 开发环境管理器：薄 CLI（`envup`，~265 行）+ 共享库（`lib.sh`，~226 行）+ 可插拔模块（`modules/<name>/{meta,install,uninstall}.sh + files/`），配置以软链落到 `$HOME`，支持按 profile / 模块 安装、卸载、升级。

经 `/understand` 全量分析（知识图谱 84 节点 / 142 边）+ 源码通读，结论：

- **内核可靠性工程扎实**（详见 §4.1）：备份不覆盖、幂等、可逆、网络超时兜底、dry-run 全覆盖、跨平台包管理、`meta.sh` 单一真源、nvim 插件钉版本可复现。
- **缺"工程化外壳"**：无测试、无 CI、无静态检查门禁、无版本/发布机制、无机器可读的可控接口、社区治理与文档不足。

一句话：内核是"能用且讲究"的，但缺少**让它可持续演进、可被信任、可被扩展**的系统工程层。本计划补齐这一层。

## 2. 目的与成功标准

**总目标**：把 envup 打磨成**优秀、可控、可扩展**的开源项目，且**不削弱**现有核心保证（§4.1 的六项不变量）。

**成功标准**（收尾逐项对照 `REFACTOR_BASELINE.md`）：

| # | 维度 | 可度量判据 |
|---|---|---|
| S1 | 可信 | P0 全清零；多平台 CI 持续绿；核心函数有单测；`shellcheck` 无未豁免告警 |
| S2 | 可控 | `envup --version` 输出；`envup status --json` 输出合法 JSON；`ENVUP_LOG_LEVEL` 生效；`upgrade` 可钉 tag |
| S3 | 可扩展 | `envup doctor` 能查出人为植入的模块错误；profile 无重复；新增网络入口默认走 `gh_url()` |
| S4 | 不回退 | 六项不变量在重构后仍由测试守护（§4.1 每项都有对应测试） |

## 3. 设计原则与约束

1. **先建网，再重构**：阶段 1 的测试 + CI 是后续一切改动的前提。没有回归网之前，不碰核心逻辑。
2. **保持哲学**：坚持"薄 CLI + 单库 + 模块"的极简结构；不引入运行期重型依赖（测试期依赖 bats/shellcheck 仅在 CI）。
3. **小步开发、按章聚合**：开发过程中可小步打锚点提交，但每个章节最终**聚合为一个 commit**（见 §6.2）；每个工作项自带验收；阶段可独立并回 / 回滚。
4. **不破坏既有保证**：任何改动不得削弱 §4.1 六项不变量；改动前先有覆盖该不变量的测试。
5. **向后兼容**：现有命令行为、环境变量、manifest 格式默认保持兼容；破坏性变更需在 CHANGELOG 标注并给迁移路径。
6. **文档随代码走**：涉及行为的改动同步更新 README / CONTRIBUTING / ARCHITECTURE。
7. **对照驱动验收**：唯一"做完了"的判据是 `REFACTOR_BASELINE.md` 的完成判据，不凭感觉。

---

## 4. 前期调研 · 现状勘察

> 这一节是本计划的地基。目的：把"要改的地方"和"绝不能改坏的地方"都定位清楚，让后续每个工作项都建立在事实而非猜测上。

### 4.1 必须守护的六项不变量（回归网要覆盖的对象）

这些是 envup 的价值所在，重构中**必须由测试守护、不得回退**：

| # | 不变量 | 代码位置 | 期望行为 |
|---|---|---|---|
| I1 | **备份不覆盖** | `lib.sh` `_link()`（~L72-91） | 目标是真实文件/目录时，先 `mv` 到 `~/.dotfiles_backup/<ts>/` 再建链 |
| I2 | **幂等** | `lib.sh` `_link()`（~L79-81） | 已正确指向源的软链，重跑为 no-op |
| I3 | **可逆** | `lib.sh` `unlink_safe()` / `is_envup_link()`（~L113-119） | 只删指向仓库内部的软链，绝不删用户真实文件 |
| I4 | **dry-run 全覆盖** | `lib.sh` 各 helper 对 `ENVUP_DRY_RUN` 的判断 | 任一命令 `--dry-run` 不产生副作用 |
| I5 | **依赖解析正确** | `lib.sh` `resolve_order()` / `_visit()`（~L198-209） | DEPENDS 排在模块前、去重、有环不死循环 |
| I6 | **单一真源** | `modules/{tmux,zsh}/meta.sh` 的 `TMUX_PLUGINS`/`ZSH_PLUGINS` | install 与 uninstall 共用同一份插件清单，不漂移 |

### 4.2 问题再核实（对评审结论的校准）

重构前必须先核实每个"问题"是否真实、边界是否准确——避免为伪问题投入。

| 基线编号 | 原判断 | 核实结论 | 证据 / 修正 |
|---|---|---|---|
| P0-1 测试 | 无自动化测试 | **成立** | 仓库无 `tests/`；`CONTRIBUTING.md` 仅建议手动 `bash -n` |
| P0-2 CI | 无 CI | **成立** | 无 `.github/` 目录 |
| P0-3 shellcheck | 无静态检查 | **成立** | 无 `.shellcheckrc`；见 §4.4 预勘 |
| P0-4 版本 | 无版本机制 | **成立** | 无 `VERSION`/`CHANGELOG`；`envup` 无 `--version`；`cmd_upgrade` 直接 `git pull`（`envup` ~L165） |
| P1-1 可控接口 | 无 JSON/日志级别 | **成立** | `cmd_status` 只输出彩色文本（`envup` ~L184-198）；`log_*` 无级别开关（`lib.sh` ~L21-26） |
| P1-2 profile 重复 | "与 DEPENDS 重复" | **修正** | DEPENDS 只表达"前置依赖"（`atuin/zoxide → zsh`），无法据此推导 `tmux/fzf/nvim`。真正的重复是 **profile 之间**：`full` 复制了 `standard` 的 6 项（`profiles/standard.sh`、`profiles/full.sh`）。方案改为 **profile 组合**（见 WI-3.1） |
| P1-3 网络地域 | URL 硬编码无镜像 | **成立** | 6 处入口，见 §4.3 |
| P1-4 doctor | 无模块校验 | **成立** | 无校验命令；模块约定（function-wrap 等）仅靠 `CONTRIBUTING.md` 口头约束 |
| P2-1 lib.sh 膨胀 | 单文件无边界 | **降级** | 现 ~226 行且**已有清晰分区注释**（logging/platform/symlink/block/network/submodule/manifest/modules）。暂不拆分，改为"固化分区契约 + 设上限阈值"（见 WI-4.5） |
| P2-6 manifest schema | 纯文本无版本 | **成立但低危** | `lib.sh` `manifest_*`（~L180-183）纯文本行。加 schema 需兼容迁移 |
| **新增 N-1** | （评审未列）平台探测重复 | **成立** | `lib.sh`（~L32-38，install 期 bash）与 `modules/zsh/files/.zshrc.d/platform.zsh` `_detect_platform()`（~L8-22，运行期 zsh）**各写一份** macos/wsl2/docker/linux 判定，逻辑会漂移。见 WI-3.4 |

### 4.3 网络入口清单（WI-3.3 的改造对象）

envup 自身代码（不含 vendored 插件子模块）的外部网络入口：

| # | 位置 | URL | 说明 |
|---|---|---|---|
| U1 | `modules/nvim/install.sh` ~L37 | `github.com/folke/lazy.nvim.git` | lazy.nvim 自举 |
| U2 | `modules/nvim/files/init.lua` ~L8 | `github.com/folke/lazy.nvim.git` | nvim 首启自举（Lua 侧） |
| U3 | `modules/zsh/install.sh` ~L64 | `raw.githubusercontent.com/ohmyzsh/...` | Oh-My-Zsh 安装器 |
| U4 | `modules/zoxide/install.sh` ~L32 | `raw.githubusercontent.com/ajeetdsouza/...` | zoxide 安装器 |
| U5 | `modules/fzf/install.sh` ~L37 | `github.com/junegunn/fzf.git` | fzf 克隆 |
| U6 | `.gitmodules` | 7 个 `github.com/...` | zsh/tmux 插件子模块 |
| （非目标） | `modules/atuin/install.sh` ~L71 | `setup.atuin.sh` | 非 GitHub，镜像化收益低，仅保留 skip 逃生舱 |

### 4.4 shellcheck 预勘（WI-1.1 的已知告警）

对 envup 自身脚本预跑 shellcheck 预计出现的告警类别与处置策略：

| 告警 | 触发点 | 处置 |
|---|---|---|
| SC1090/SC1091（无法跟踪 source） | `source ./meta.sh`、`source "$script"`（`lib.sh` `run_module_hook`） | `.shellcheckrc` 开 `external-sources=true` + 用 `-x`；对动态路径加 `# shellcheck source=/dev/null` |
| SC2154（变量未赋值即用） | install/uninstall 用 `TMUX_PLUGINS`/`ZSH_PLUGINS`（来自 `source meta.sh`） | 已有 `# shellcheck source=meta.sh` 指令；必要时 `disable=SC2154` |
| SC2034（变量赋值未使用） | `meta.sh` 的 `NAME`/`DESCRIPTION`（被 `module_meta` 间接读取） | 文件级 `# shellcheck disable=SC2034` |
| SC2016（单引号内 `$` 不展开） | atuin/zoxide 的 `bash -c '...curl...'`（有意不展开） | 确认是有意，逐行 `# shellcheck disable=SC2016` |

> 结论：预计**无需改变行为**即可通过，主要是加指令与 `.shellcheckrc`。这正是先做 P0-3 的价值——把这些噪音一次性固化，之后每次改动都干净。

---

## 5. 分阶段实施

> 每个工作项（WI）格式统一：**现状 → 根因 → 方案 → 步骤 → 验收**。验收给出可执行断言。
> 每个阶段收尾：更新 `REFACTOR_BASELINE.md` 状态 + 跑该阶段验收 + 提交。

### 阶段 0 · 基线与准备（已完成）

- [x] tag `baseline/pre-refactor` 冻结提交
- [x] `docs/REFACTOR_BASELINE.md` 冻结问题清单
- [x] `refactor` 分支
- [x] 知识图谱入库 + scratch 目录 `.gitignore`
- [x] 本计划书

**验收**：`git diff baseline/pre-refactor` 可随时对照。

---

### 阶段 1 · 质量护栏（P0，先建网）

目标：把"跨平台可用"从声明变为**每次提交都自动验证**的事实；为后续所有重构提供回归网。

#### WI-1.1 · shellcheck 门禁（→ P0-3）

- **现状**：无 `.shellcheckrc`；从未静态检查过。
- **根因**：bash 易积累隐患（未加引号、`local` 误用、可移植性问题），无门禁则每次改动都可能引入。
- **方案**：加仓库级 `.shellcheckrc`；对每个脚本清零告警（改代码或加豁免指令，遵循 §4.4）。
  ```
  # .shellcheckrc
  external-sources=true
  # 允许动态 source（module_meta / run_module_hook 的运行期 source）
  disable=SC1091
  ```
- **步骤**：
  1. 本地对 `envup lib.sh modules/**/*.sh profiles/*.sh completions/_envup` 跑 `shellcheck -x`。
  2. 按 §4.4 逐类消解；真实问题改代码，噪音加最小范围 `disable` 指令。
  3. 写 `scripts/lint.sh` 汇总（供本地与 CI 共用）。
- **验收**：`shellcheck -x envup lib.sh modules/**/*.sh profiles/*.sh completions/_envup` 退出码 0。

#### WI-1.2 · 单元测试（→ P0-1，守护 I1/I2/I3/I5/I6）

- **现状**：核心逻辑零测试。
- **根因**：`lib.sh` 的纯函数（依赖解析、软链、manifest、块编辑）是全项目最关键、最该被守护的部分，却无任何断言。
- **方案**：引入 [bats-core](https://github.com/bats-core/bats-core)，`tests/unit/*.bats`，用临时 `HOME`/`ENVUP_HOME` 沙箱。目标函数与最小用例：

  | 目标 | 用例 |
  |---|---|
  | `resolve_order`(I5) | ①单模块；②`atuin`→前置 `zsh`；③去重；④**构造环不死循环**；⑤未知模块被跳过 |
  | `_link`/`safe_link`(I1/I2) | ①链到空位；②目标是真实文件→备份到 backup 目录；③已正确链→no-op；④`ENVUP_DRY_RUN=1` 无副作用 |
  | `unlink_safe`/`is_envup_link`(I3) | ①删自建软链；②**指向仓库外的软链/真实文件→拒删**；③dry-run |
  | `block_set`/`block_del` | ①插入块；②重复 set 幂等（不重复追加）；③del 干净移除；④dry-run |
  | `manifest_*` | add/has/remove/list 往返；重复 add 幂等 |
  | `module_meta`/`module_deps` | 正确读出标量与数组字段 |
- **步骤**：
  1. `tests/test_helper.bash`：搭建临时 `ENVUP_HOME`（含伪模块）与临时 `HOME`。
  2. 逐函数写 `.bats`。
  3. `scripts/test.sh` 一键跑。
- **验收**：`bats tests/unit` 全绿；上述每个不变量至少一个用例。

#### WI-1.3 · 集成测试（→ P0-1/P0-2，守护 I4 + 跨平台）

- **现状**：install/uninstall 全链路从未自动化验证。
- **方案**：
  - `tests/integration/dry-run.bats`：临时 `HOME` 下 `./envup install -p {minimal,standard,full} --dry-run` 全部退出 0 且无写盘。
  - `tests/integration/smoke.sh`：容器内**真装**冒烟 `install → status → uninstall`，断言软链建立/移除、manifest 增删、backup 生成。
- **步骤**：先 dry-run（任何平台可跑），再容器冒烟（CI 矩阵里跑）。
- **验收**：dry-run 套件本地绿；冒烟脚本在至少一个容器发行版通过。

#### WI-1.4 · CI 矩阵（→ P0-2）

- **现状**：无 `.github/workflows`。
- **方案**：`.github/workflows/ci.yml`，`push`/`pull_request` 触发，四类 job：
  1. **lint**：`scripts/lint.sh`（shellcheck + `bash -n`）。
  2. **unit**：装 bats → `bats tests/unit`。
  3. **dry-run**：`bats tests/integration/dry-run.bats`。
  4. **matrix-smoke**：
     - `ubuntu-latest`、`macos-latest`（**注意：mac runner 是 bash 3.2 → 先 `brew install bash`，验证 envup 的 re-exec 逻辑**）。
     - 容器：`fedora`、`archlinux`、`alpine`（覆盖 dnf/pacman/apk；alpine 需先装 bash）。
- **步骤**：先让 lint+unit+dry-run 绿，再逐个补容器矩阵。
- **验收**：PR 上四类 job 全绿；徽章可引用（WI-2.2）。

**阶段 1 出口**：P0-1/2/3 在基线清单标记"已解决"；CI 绿。

---

### 阶段 2 · 可信与可控（P0-4 + P1-1）

#### WI-2.1 · 版本与发布机制（→ P0-4）

- **现状**：无 `VERSION`；`envup` 无 `--version`；`cmd_upgrade`（`envup` ~L165）只 `git pull --recurse-submodules`，无法锁版本。
- **方案**：
  - 新增 `VERSION`（如 `0.1.0`）。
  - `envup` dispatch（~L256）与 `usage` 支持 `--version`/`-V`：读取 `$ENVUP_HOME/VERSION`，无则回退 `git describe --tags`。
  - `CHANGELOG.md`（Keep a Changelog 风格）；文档化 release 流程（更新 VERSION+CHANGELOG → 打 `vX.Y.Z` tag）。
  - `cmd_upgrade` 增加 `--ref <tag|branch>`：`git fetch --tags && git checkout <ref>` 后再 reinstall；缺省保持 `pull` 行为（向后兼容）。
  ```bash
  # envup dispatch 片段（新增）
  -V|--version) echo "envup $(cat "$ENVUP_HOME/VERSION" 2>/dev/null \
                  || git -C "$ENVUP_HOME" describe --tags --always 2>/dev/null \
                  || echo unknown)"; exit 0 ;;
  ```
- **验收**：`envup --version` 输出版本；`CHANGELOG.md` 有条目；`envup upgrade --ref <tag> -n` 显示会 checkout 该 ref。

#### WI-2.2 · 可信展示（README 徽章 + LICENSE）

- **方案**：README 顶部加 CI / License / 平台 徽章；显式呈现 MIT。
- **验收**：README 渲染出徽章；徽章 CI 链接指向 WI-1.4 的 workflow。

#### WI-2.3 · 可控接口：`status --json` + `ENVUP_LOG_LEVEL`（→ P1-1）

- **现状**：`cmd_status`（`envup` ~L184-198）仅彩色文本；`log_*`（`lib.sh` ~L21-26）恒打印。
- **方案**：
  - `cmd_status --json`：输出 `{platform,arch,pkg,modules:[{name,description,installed}],profiles:[...]}`；JSON 模式**强制关色**并只走 stdout。
  - `ENVUP_LOG_LEVEL`（debug<info<warn<error，默认 info）：在 `_logf` 与各 `log_*` 前加级别闸；不影响命令正常 stdout。
  ```bash
  # lib.sh 片段（新增）
  _lvl() { case "$1" in debug)echo 0;;info)echo 1;;warn)echo 2;;error)echo 3;;*)echo 1;;esac; }
  _should_log() { [[ "$(_lvl "$1")" -ge "$(_lvl "${ENVUP_LOG_LEVEL:-info}")" ]]; }
  # log_info() { _should_log info && printf ... ; _logf INFO "$*"; }
  ```
- **验收**：`envup status --json | jq .` 通过；`ENVUP_LOG_LEVEL=warn envup status` 隐藏 info 行；`ENVUP_LOG_LEVEL=debug` 更详细。

**阶段 2 出口**：P0-4、P1-1 标记"已解决"。

---

### 阶段 3 · 可扩展性（P1）

#### WI-3.1 · profile 组合去重（→ P1-2，修正后）

- **现状**：`profiles/full.sh` 复制 `standard` 的 6 项再加 `nvim`；两处需手工同步。
- **根因**：profile 之间无组合机制，只能整份复制。
- **方案**：让 profile 可"继承"。`load_profile`（`lib.sh` ~L213）在 source 前提供 `use_profile <name>` 辅助（把另一个 profile 的 MODULES 并入），从而：
  ```bash
  # profiles/full.sh
  use_profile standard          # 复用 standard 的模块集
  MODULES+=(nvim)
  ```
  行为等价由 WI-1.2/1.3 的测试保证（安装集合与旧版一致）。
- **验收**：`envup install -p full -n` 的模块顺序与基线一致；`profiles/full.sh` 不再重复列 6 项。

#### WI-3.2 · `envup doctor` 模块校验器（→ P1-4）

- **现状**：模块约定仅靠 `CONTRIBUTING.md` 口头约束，写错要到运行时才炸。
- **方案**：新增 `cmd_doctor`，对每个模块静态校验：
  1. `meta.sh` 含 `NAME`/`DESCRIPTION`；`DEPENDS`/`SELF_DEPS`/`CLEAN_PATHS` 若定义须为数组。
  2. install/uninstall 若用了顶层 `local` 必须 function-wrap（`run_module_hook` 用非函数子 shell，顶层 `local` 会炸）。
  3. `DEPENDS` 指向的模块存在；无依赖环。
  4. `CLEAN_PATHS` 不含已知用户数据目录（如 `~/.local/share/atuin`、`~/.local/share/zoxide`、resurrect 目录）——防"clean 删历史"。
  5. 每个脚本 `bash -n` 通过。
  - 退出码：0 全过 / 1 有错；`--module <name>` 限定单模块。
- **验收**：对人为植入错误（缺字段、顶层 `local`、`CLEAN_PATHS` 含用户数据）能报出并非 0 退出；CI 增加 `envup doctor` job。

#### WI-3.3 · 镜像/代理开关 `ENVUP_GH_MIRROR`（→ P1-3）

- **现状**：§4.3 六处入口硬编码。
- **方案**：`lib.sh` 加 `gh_url <url>`：当 `ENVUP_GH_MIRROR` 设置时把 `github.com`/`raw.githubusercontent.com` 前缀改写为镜像；否则原样返回。改造 U1、U3、U4、U5 调用点走 `gh_url`；U2（init.lua）读环境变量 `ENVUP_GH_MIRROR` 做同样改写；U6（`.gitmodules`）在文档中给出 `git config --global url."<mirror>".insteadOf https://github.com/` 方案（子模块 URL 不宜写死镜像）。
  ```bash
  # lib.sh 片段（新增）
  gh_url() { local u="$1"; [[ -n "${ENVUP_GH_MIRROR:-}" ]] || { echo "$u"; return; }
    echo "$u" | sed -E "s#https://(raw\.githubusercontent\.com|github\.com)#${ENVUP_GH_MIRROR%/}/\1#"; }
  ```
- **验收**：`ENVUP_GH_MIRROR=https://mirror.example` 下，install `-n`/日志显示改写后的 URL；未设置时行为不变。

#### WI-3.4 · 平台探测去重（→ 新增 N-1）

- **现状**：`lib.sh`（~L32-38）与 `platform.zsh`（~L8-22）各写一份 macos/wsl2/docker/linux 判定，规则会漂移。
- **约束**：一个是 install 期 bash、一个是运行期 zsh，无法直接共享函数。
- **方案**：抽出**单一判定规范**（同一套判定顺序与依据的注释/文档），两处实现严格对齐；加一个测试断言两者对同样输入给出同样平台名（可用 fixture 模拟 `/proc/version`、`/.dockerenv`）。
- **验收**：对齐后有测试保证两处结论一致；ARCHITECTURE 记录该判定规范。

**阶段 3 出口**：P1-2/3/4 + N-1 标记"已解决"。

---

### 阶段 4 · 打磨与社区（P2）

| WI | 内容 | 验收 |
|---|---|---|
| WI-4.1（P2-2） | `.github/` 补 issue/PR 模板、`CODE_OF_CONDUCT.md`、`SECURITY.md` | 文件齐全，PR 走模板 |
| WI-4.2（P2-3） | README 加 asciinema/GIF 演示 + 30 秒快览 | README 顶部有可视演示 |
| WI-4.3（P2-4） | 模块文档规范：每模块 `meta.sh` 顶注 + 必要时 `docs/<module>.md` | 每模块可一句话说清用途与副作用 |
| WI-4.4（P2-5） | `README.zh-CN.md`，与英文同步 | 双语可切换 |
| WI-4.5（P2-1，降级） | 固化 `lib.sh` 分区契约 + 设行数上限提醒（如 CI 软告警 >400 行考虑拆分） | ARCHITECTURE 记录分区；CI 有阈值提示 |
| WI-4.6（P2-6） | manifest 增加 `# schemaVersion: N` 头 + 向后兼容读取 | 旧 manifest 仍可读；新写带版本 |

**阶段 4 出口**：P2 各项在基线清单确认（允许标注"留待后续里程碑"）。

---

### 阶段 5 · 最终评估

1. 逐项回填 `REFACTOR_BASELINE.md` 状态，确认 P0/P1 = 已解决。
2. 重跑 `/understand`，与基线知识图谱 diff，确认无结构性回退。
3. 复核六项不变量（§4.1）仍成立——由测试证明，非人工确认。
4. 重新为"开源就绪度"打分并记录（对照基线 C）。
5. 决定 P2 去留；把 `refactor` 合入 `main`；打首个正式 release tag（如 `v0.1.0`）。

---

## 6. 分支与提交策略

### 6.1 分支

- 主重构分支：`refactor`。
- 阶段较大时开子分支：`refactor/phase-1-ci`、`refactor/phase-2-versioning`…，完成并回 `refactor`。
- 全部阶段完成、最终评估通过后，再 `refactor → main` 并发 release。

### 6.2 提交粒度（重要）

- **提交不宜过密**：不要"随手改个变量就一个 commit"——碎提交淹没历史，不利于回溯与 review。
- **每个章节（阶段）最终只保留 1 个 commit**。
- 章节内有多个子任务时，开发过程中可先按子任务打**临时锚点提交**，命名如 `phase1: 1.1 shellcheck`、`phase1: 1.2 unit tests`，用于阶段性记录与回退。
- 待**本章节全部改造完成且验收通过**后，用 `git rebase -i` 或 `git reset --soft <章节起点>` 把这些锚点 **squash / amend 合并为一个** commit，再进入下一章。
- 仅对**未 push 的本地历史**做合并；已 push 的不强推（除非明确要求）。

### 6.3 提交信息规范

- **简洁、精确、专业**：一行主题（祈使句，≤ 72 字符）+ 必要正文说明"为什么/改了什么"，避免流水账。
- 前缀：`feat:` / `fix:` / `refactor:` / `test:` / `ci:` / `docs:` / `chore:`。
- 一个 commit = 一个可独立理解的变更单元（一个章节）。正文可用要点列出该章节包含的子任务。

### 6.4 文档同步（强约束）

- 任何影响**行为 / 接口 / 流程**的改动，必须在**同一个 commit 内**同步更新相关文档：`README` / `CONTRIBUTING` / `ARCHITECTURE` / 本计划书 / 基线清单。
- 每个章节收尾**必须**回填 `REFACTOR_BASELINE.md` 的状态列与本计划书 §9 进度——**文档滞后即视为该章节未完成**。
- 代码与文档不同步的提交不合入 `refactor`。

## 7. 验收与对照机制

- **唯一对照源**：`docs/REFACTOR_BASELINE.md` 的问题表（「验证方式」列）与「最终评估清单」。
- 每完成一个 WI：跑其验收断言 → 更新基线表状态与验证记录 → 勾选 §9 进度。
- **不跳步**：阶段 1 回归网未就绪，不进入阶段 2+ 的核心改动。

## 8. 风险与回滚

| 风险 | 应对 |
|---|---|
| 重构引入回归 | 阶段 1 先建网；核心改动均在 CI 保护下合并 |
| 破坏跨平台行为 | CI 矩阵覆盖 mac(bash3.2 re-exec) + fedora/arch/alpine；冒烟集成 |
| `status --json` / 日志级别改动影响现有输出 | 默认行为不变；新行为仅在显式 flag/env 下生效；测试覆盖两条路径 |
| 镜像改写破坏默认安装 | `gh_url` 未设 env 时原样返回；测试覆盖"未设置=零改动" |
| 偏离设计哲学 | 原则 §3.2；ARCHITECTURE 同步评审 |
| 需要回到起点 | `git diff/checkout baseline/pre-refactor` 或从 tag 重开分支 |

## 9. 工作项索引与进度总览

| WI | 对应基线 | 阶段 | 一句话 | 状态 |
|---|---|---|---|---|
| WI-1.1 | P0-3 | 1 | shellcheck 门禁 + `.shellcheckrc` | ✅ 已完成 |
| WI-1.2 | P0-1 | 1 | bats 单测（守护 I1/I2/I3/I5/I6） | ✅ 已完成（26 例） |
| WI-1.3 | P0-1 | 1 | 集成测试（dry-run 全 profile + 容器冒烟） | ✅ 已完成 |
| WI-1.4 | P0-2 | 1 | CI 矩阵（lint/unit/dry-run/matrix-smoke） | ✅ 已完成（绿标待 push 验证） |
| WI-2.1 | P0-4 | 2 | VERSION + `--version` + CHANGELOG + `upgrade --ref` | ✅ 已完成 |
| WI-2.2 | P0-4/P2-3 | 2 | README 徽章 + LICENSE 展示 | ✅ 已完成 |
| WI-2.3 | P1-1 | 2 | `status --json` + `ENVUP_LOG_LEVEL` | ✅ 已完成 |
| WI-3.1 | P1-2 | 3 | profile 组合去重 | ✅ 已完成 |
| WI-3.2 | P1-4 | 3 | `envup doctor` 模块校验 | ✅ 已完成 |
| WI-3.3 | P1-3 | 3 | `ENVUP_GH_MIRROR` 镜像开关 | ✅ 已完成 |
| WI-3.4 | N-1 | 3 | 平台探测去重 | ✅ 已完成（对齐+测试） |
| WI-4.1 | P2-2 | 4 | 社区模板 | ✅ 已完成 |
| WI-4.2 | P2-3 | 4 | 演示 GIF/快览 | ✅ 已完成（快览+录制指引；GIF 按需） |
| WI-4.3 | P2-4 | 4 | 模块文档规范 | ✅ 已完成 |
| WI-4.4 | P2-5 | 4 | 中文 README | ✅ 已完成 |
| WI-4.5 | P2-1 | 4 | lib.sh 分区契约 + 阈值 | ✅ 已完成 |
| WI-4.6 | P2-6 | 4 | manifest schemaVersion | ✅ 已完成 |
| WI-6.1 | N-2 | 6 | 系统性防卡死（模块看门狗 + pkg 超时） | ✅ 已完成 |

**阶段进度**：

- [x] 阶段 0 · 基线与准备
- [x] 阶段 1 · 质量护栏（WI-1.1 ~ 1.4）— 本地全绿（lint / 26 单测 / 4 dry-run / git smoke）；CI 绿标待首次 push 验证
- [x] 阶段 2 · 可信与可控（WI-2.1 ~ 2.3）— 版本/发布机制、`upgrade --ref`、`status --json`、`ENVUP_LOG_LEVEL`；39 bats 全绿
- [x] 阶段 3 · 可扩展性（WI-3.1 ~ 3.4）— profile 组合、`envup doctor`、`ENVUP_GH_MIRROR`、平台探测对齐；53 bats 全绿
- [x] 阶段 4 · 打磨与社区（WI-4.1 ~ 4.6）— 社区模板、快览、模块文档、中文 README、lib 分区契约、manifest schema；56 bats 全绿
- [x] 阶段 5 · 最终评估 — 全门禁绿、0 回归、六不变量有测试守护、评分 C→A-；详见 [`REFACTOR_REPORT.md`](./REFACTOR_REPORT.md)
- [x] 阶段 6 · 健壮性补强（WI-6.1 / N-2）— 系统性防卡死：模块钩子看门狗 + pkg_install 超时；`tests/unit/timeout.bats` 守护
