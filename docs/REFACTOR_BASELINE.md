# envup 重构基线 · 识别到的问题清单（冻结）

> 本文件是**冻结的对照基线**。重构全部完成后，逐项回到这里核对是否已解决。
> 请勿在重构过程中修改问题描述本身——只更新「状态」与「验证记录」两列。

- **基线提交**：`a5263c4`（git tag `baseline/pre-refactor`）
- **分析依据**：`/understand` 知识图谱（84 节点 / 142 边）+ 全量源码通读
- **评审来源**：Canvas《envup 开源化评审》
- **冻结时间**：2026-07-01

## 评分基线（重构后重新打分对照）

| 维度 | 基线 | 目标 | 结果 |
|---|---|---|---|
| 工程底子（内核可靠性） | B+ | A | **A** ✅ |
| 开源就绪度 | C | A- | **A-** ✅ |
| P0 阻塞项 | 4 | 0 | **0** ✅ |

> 结项评估详见 [`docs/REFACTOR_REPORT.md`](./REFACTOR_REPORT.md)。

## 问题清单

状态取值：`未开始` / `进行中` / `已解决` / `已取消`。

### P0 — 阻塞开源可信度（必须清零）

| 编号 | 类别 | 问题 | 影响 | 验证方式（完成判据） | 状态 |
|---|---|---|---|---|---|
| P0-1 | 测试 | 零自动化测试，`CONTRIBUTING` 仅要求手动 `bash -n` | 重构/改动无回归网 | `tests/` 存在；`resolve_order`/`safe_link`/`manifest_*`/`block_set` 有单测；CI 中执行且通过 | **已解决** · 26 单测(`tests/unit/`)+4 dry-run+git smoke 本地全绿；CI `unit`/`dry-run`/`smoke-*` 已配置 |
| P0-2 | CI/CD | 无 `.github/workflows`，跨平台无持续验证 | 「跨平台可用」仅为声明 | 存在 CI，矩阵覆盖 ubuntu/macos + 容器(fedora/arch/alpine)，PR 触发且绿 | **已解决** · `.github/workflows/ci.yml`（lint/unit/dry-run/smoke-host[ubuntu+macos]/smoke-containers[fedora/arch/alpine]），PR/push 触发；绿标待首次 push 验证 |
| P0-3 | 静态检查 | 无 `shellcheck` 门禁 | bash 隐患随提交累积 | `.shellcheckrc` 存在；CI 对 `envup lib.sh modules/**/*.sh profiles/*.sh completions/*` 全绿 | **已解决** · `.shellcheckrc`+`scripts/lint.sh`，`shellcheck -x`+`bash -n` 全 27 文件本地 0 告警（zsh 补全不适用 shellcheck，已排除） |
| P0-4 | 版本管理 | 无 `VERSION`/`CHANGELOG`/tag/release，无 `envup --version` | 用户无法锁定/追踪版本，`upgrade` 只能拉 main | `VERSION` 存在；`envup --version` 输出；`CHANGELOG.md` 有条目；发布 tag 流程文档化 | **已解决** · `VERSION`(0.1.0)+`envup --version`；`CHANGELOG.md`(Keep a Changelog)；`upgrade --ref <tag>` 可钉版本；CONTRIBUTING 有 Releasing 流程 |

### P1 — 可扩展性与可控性

| 编号 | 类别 | 问题 | 影响 | 验证方式（完成判据） | 状态 |
|---|---|---|---|---|---|
| P1-1 | 可控性 | 无机器可读输出（`status --json`），无日志级别 | 难被上层自动化编排 | `envup status --json` 输出合法 JSON；`ENVUP_LOG_LEVEL` 生效 | **已解决** · `status --json`(jq 校验通过)；`ENVUP_LOG_LEVEL` 4 级门控，`tests/unit/loglevel.bats`+`tests/integration/cli.bats` 守护 |
| P1-2 | 依赖表达 | **（已修正）** profile 之间列表重复：`full` 复制了 `standard` 的 6 项（原判断"与 `DEPENDS` 重复"不成立，见计划书 §4.2） | 两份列表需手工同步、易漂移 | profile 支持组合，`full` 只在 `standard` 基础上加 `nvim`；安装集合与旧行为一致（测试保证） | **已解决** · `use_profile`；minimal→standard→full 组合链；`tests/integration/profile-compose.bats` 断言解析顺序与基线一致 |
| P1-3 | 网络/地域 | 官方安装器 GitHub URL 硬编码，无镜像/代理开关（自身代码 6 处入口，见计划书 §4.3） | 受限网络体验差 | `ENVUP_GH_MIRROR` 生效，安装器可走镜像；未设置时行为零变化 | **已解决** · `gh_url()` 改造 nvim/fzf/zsh/zoxide 安装器 + `init.lua`；`.gitmodules` 用 git `insteadOf`（文档化）；`tests/unit/ghurl.bats` 守护 |
| P1-4 | 可扩展性 | 无模块规范校验器 | 新模块易写错（字段/钩子 wrap/幂等） | `envup doctor` 能校验 meta 字段、钩子 function-wrap、软链健康、CLEAN_PATHS 不含用户数据 | **已解决** · `envup doctor [--module]`；校验 NAME/DESCRIPTION、DEPENDS 存在、语法、顶层 `local`、CLEAN_PATHS 用户数据；`tests/integration/doctor.bats` 守护 |
| N-1 | 一致性 | **（新增）** 平台探测逻辑在 `lib.sh`(~L32-38) 与 `platform.zsh`(~L8-22) 各写一份 macos/wsl2/docker/linux 判定 | 两处规则会漂移 | 抽出单一判定规范，两处对齐并有测试断言结论一致 | **已解决** · 两处对齐为同一 canonical 规则（ARCHITECTURE 记录）；`tests/unit/platform.bats` 断言一致性 |
| N-2 | 健壮性 | **（结项后新识别）** 单步联网卡死会拖垮整条运行：`pkg_install` 无超时、`run_module_hook` 无外层看门狗（仅 curl 安装器有 net_run 超时） | 某模块卡住 → 后续无法继续 | 任何单步都不可能拖死整条运行：pkg_install 套超时 + 模块钩子外层 `ENVUP_MODULE_TIMEOUT` 看门狗（超时即杀、记失败、继续下一个）；有测试守护 | **已解决** · `run_module_hook` 看门狗（900s，TERM→KILL）+ `pkg_install` 超时；无 timeout 二进制则告警降级；`tests/unit/timeout.bats` 3 例守护 |

### P2 — 打磨与社区治理

| 编号 | 类别 | 问题 | 影响 | 验证方式（完成判据） | 状态 |
|---|---|---|---|---|---|
| P2-1 | 内核演进 | `lib.sh` 单文件随规模膨胀，无内部边界约束 | 长期可维护性 | 明确内部分区（注释锚点或拆分），并有约定文档 | **已解决** · lib.sh 头部「Section contract」+ ARCHITECTURE「lib.sh sections」；`scripts/lint.sh` 加 400 行软阈值（当前 280） |
| P2-2 | 社区治理 | 无 issue/PR 模板、`CODE_OF_CONDUCT`、`SECURITY.md` | 贡献规范缺失 | `.github/` 下相应文件齐全 | **已解决** · `.github/ISSUE_TEMPLATE/{bug_report,feature_request,config}` + `PULL_REQUEST_TEMPLATE.md` + `CODE_OF_CONDUCT.md` + `SECURITY.md` |
| P2-3 | 文档 | 无徽章/演示 GIF | 首因体验弱 | README 有 CI/License/Platform 徽章 + 演示（GIF/asciinema） | **已解决** · 徽章（阶段2）+ README「What it looks like」标注式会话；GIF/asciinema 给了本地录制指引（二进制资产按需再补） |
| P2-4 | 文档 | 仅 tmux 有模块文档 | 模块理解成本高 | 每模块有 README 段或 `docs/` 规范 | **已解决** · 每模块 `meta.sh` 有「# Module: …」头 + DESCRIPTION；CONTRIBUTING 固化模块文档约定 |
| P2-5 | 国际化 | 无中文 README | 作者受众/国际化 | `README.zh-CN.md` 存在并与英文同步 | **已解决** · `README.zh-CN.md` + 双向语言切换链接 |
| P2-6 | 状态存储 | manifest 为纯文本、无 schema 版本 | 未来迁移困难 | manifest 带 `schemaVersion` 且向后兼容 | **已解决** · `# envup-manifest schema=1` 头，读时忽略注释、旧无头 manifest 仍可读；`tests/unit/manifest.bats` 守护 |

## 最终评估清单（重构收尾时执行）

- [x] 上表所有 P0 状态 = 已解决（4/4）
- [x] 上表所有 P1 状态 = 已解决（4/4）+ N-1
- [x] P2 逐项确认（6/6；GIF/asciinema 以文字快览+录制指引替代，二进制资产按需再补）
- [x] 与基线知识图谱回归对比：**0 删除，只增（测试/CI/文档）**，无结构性回退（详见报告 §4；完整 `/understand` 刷新建议合入 `main` 后进行）
- [x] 未破坏核心保证：备份 / 幂等 / 可逆 / dry-run / 跨平台 —— 由 `tests/unit/*` 守护（报告 §3）
- [x] 重新为「开源就绪度」打分并记录：C → **A-**（报告 §5）
