# Changelog

本项目遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [0.15.0] — 2026-09-16

- 新增 `conatus_compaction` 包：压缩能力缝（从 `conatus_agent` 拆出，对应 dsh
  `packages/compaction/compaction`）。
- `CompactionEngine`（服务键 `'compaction'`）：`compactIfNeeded` / `summaryOf` /
  `forget` / `keepRecent`；`Compactor` 为默认实现，`provideCompaction` 负责装配。
- 压缩在日志末尾追加 `compaction/start` → `compaction/summary` → `compaction/end`
  三个纯记录事件，滚动摘要因此可从日志重建（补上「模型可见即已记录」的缺口）；
  `checkCompactionInvariant` / `assertCompactionInvariant` 校验这三个事件。
- `balancedCutAtOrBefore` / `toolPairingBalancedBefore` / `toolPairingBalancedAfter`：
  压缩切点不劈开助手的工具调用与其 `tool/result`。
- `Summarizer` 的产出改为 `CompactionSummary`（摘要文本 + 写它的 provider / model）。
