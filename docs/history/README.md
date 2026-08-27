# 历史文档（冻结）

这里的文件记录的是**做过什么、当时为什么那样判断**，不是当前架构。它们写于
v0.1 那一轮重构，其中的文件路径有一部分在 v0.2 的模块契约 v2 里已经不存在
（`modules/*/install.sh` → `modules/*/hooks.sh`，`.zshrc.d/platform.zsh` →
编号切片 `20-platform.zsh`），别照着它们改代码。

| 文件 | 内容 |
|---|---|
| [`REFACTOR_BASELINE.md`](REFACTOR_BASELINE.md) | 动工前冻结的问题清单，验收时逐项对照 |
| [`REFACTOR_PLAN.md`](REFACTOR_PLAN.md) | 计划书：每个问题的定位 → 根因 → 方案 → 验收判据 |
| [`REFACTOR_REPORT.md`](REFACTOR_REPORT.md) | 结项评估，对照前两份 |

当前架构看 [`../ARCHITECTURE.md`](../ARCHITECTURE.md)，版本间的变化看
[`../../CHANGELOG.md`](../../CHANGELOG.md)。

放在这里而不是删掉，是因为这三份写的是取舍的**理由**——哪些方案考虑过又被否掉、
每条判断当时依据什么。代码本身留不下这些，git log 里也不会有。它们不再随代码更新，
所以也不该和会更新的文档摆在一起。
