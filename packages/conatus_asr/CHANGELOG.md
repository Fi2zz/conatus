# Changelog

本项目遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [0.15.0] — 2026-09-15

- 新增 `conatus_asr` 包，承载 ASR 能力缝 `AsrService` / `AsrProvider`、
  豆包/火山 SAUC 流式 provider、`transcribe_audio` 工具，以及可替换的
  `AsrAudioSource`（ffmpeg 麦克风采集实现）。
