# Changelog

本项目遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [0.15.0] — 2026-09-15

- 从 `conatus` 单体仓库拆分为独立包（pub workspace monorepo），
  承载 timer / logger / loader / tools / shell / fs / session /
  system-prompt / memory / database / ask-user 等基础设施插件。
