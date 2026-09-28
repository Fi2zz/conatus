# Changelog

本项目遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [未发布]

- 新增**退避重试**（`llm_retry.dart`）：`RetryingLlm` 装饰器 + `RetryPolicy` +
  `LlmErrorKind`。此前一次网络抖动 / 一次 429 / 一次 502 就让整轮失败，这是编码
  agent 最常见的失败模式。
  - **只重试有意义的失败**：限流（429 / 529）、5xx、超时与连接错误可重试；401 /
    403、缺 API Key、4xx 不可重试——换 Key 或修参数才有用，原地重试只是重复
    被拒。换提供商是另一回事，见下条。
  - 退避按 2 的幂翻倍（缺省 500ms 起 / 单次封顶 30s / ±25% 抖动）。抖动是为了
    避免并发客户端踩同一个节奏重试形成惊群。
  - 服务端给了 `Retry-After`（delta-seconds 与 HTTP-date 两种形态）就照它等，
    不叠加抖动，但仍受 `maxDelay` 约束——避免被一个写错的 `Retry-After: 3600`
    卡住一小时。
  - 流式**只在尚未产出任何事件时重试**：已 yield 的增量收不回来，静默重来只会
    让调用方看到重复内容。
  - 睡眠函数与 `Random` 均可注入，单测能断言退避序列而不真的等。
- `LlmException` 新增 `kind`（失败类别）与 `retryAfter`；未标注 `kind` 时按
  `statusCode` 推断，因此 `const LlmException('p', 'm', 429)` 就能正确判定为可
  重试。`statusCode` 由可选位置参数改为具名参数。
- wire 层：传输层失败（超时 / SocketException / `http.ClientException`）显式标注
  为 `network` 类，缺 Key 标注为 `config` 类——这两类都没有状态码，只能显式标。
- wire 层：非 200 的错误正文优先取结构化 JSON 的 `error.message`，不再把整段
  body（可能几百字符 HTML / JSON）抛给上层。
- `FallbackLlm` 移到 `llm_fallback.dart`（原 `llm.dart` 已超单文件行数约束），
  并新增 `onFallback` 回调：回退是静默发生的，宿主需要它来提示「主模型不可用，
  已切到 X」，否则用户只会看到回答风格突然变了。
- `FallbackLlm` 的流式回退补上 `emitted` 判断的显式重抛路径与非 `LlmException`
  错误的收集（此前非 `LlmException` 的错误在流式路径上会逃出汇总）。

- **LLM 调用统一走流式端点**：`OpenAiCompatibleProvider.chat()` 内部改为调用
  `chatStream()` 累积成 `LlmResult`（新增顶层 `streamChatResult`），不再发非流式
  请求；`LlmResult` 新增 `reasoning` 字段（Kimi 等模型的 `reasoning_content`），
  思考过程不再丢失。`LlmStreamDone` 携带 `provider`/`model`。
- `LlmMessage` 新增可选 `images` 字段（`LlmImage`：mimeType + base64），支持
  多模态输入；无图片时请求体保持原样（`content` 为字符串），有图片时 chat
  形态输出 `image_url` parts 数组，responses 形态追加 `input_image` 项

## [0.15.0] — 2026-09-15

- 从 `conatus` 单体仓库拆分为独立包（pub workspace monorepo），
  承载 `LlmProvider` 契约、`FallbackLlm` 回退链与豆包 / DeepSeek 实现。
