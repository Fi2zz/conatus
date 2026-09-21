# Changelog

本项目遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [未发布]

- `LlmMessage` 新增可选 `images` 字段（`LlmImage`：mimeType + base64），支持
  多模态输入；无图片时请求体保持原样（`content` 为字符串），有图片时 chat
  形态输出 `image_url` parts 数组，responses 形态追加 `input_image` 项

## [0.15.0] — 2026-09-15

- 从 `conatus` 单体仓库拆分为独立包（pub workspace monorepo），
  承载 `LlmProvider` 契约、`FallbackLlm` 回退链与豆包 / DeepSeek 实现。
