# Changelog

本项目遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [未发布]

初始实现——意图路由：先本地匹配、未命中才走完整 Agent Loop：

- `IntentRouter` / `provideIntentRouter`（服务键 `'router'`）：正则优先、
  向量兜底；命中按动作类型收口（`DirectAction` 零模型调用 /
  `ToolAction` 预置工具调用后模型收口 / `DelegateAction` 经 skill 委托），
  未命中 `RoutePass` 与未装路由器完全一致
- 接线走 `conatus_agent` 既有确定性路由 seam（`Router` / `RouteReply` /
  `RouteTools` / `RoutePass`），不修改 Agent Loop
- 嵌入 seam：`LocalEmbeddingProvider`（纯 Dart n-gram 哈希，离线确定）/
  `LlmEmbeddingProvider`（模型端点）/ `Intent.embedding`（预计算嵌入）
- `IntentLoader`：意图是数据，JSON 声明式配置（`tool` / `builtin` /
  `delegate` / `respond` 四种动作），闭包动作序列化时抛
  `IntentException('not-serializable')`
- `SkillIntentBridge` / `IntentLearner` / `ToolIntentGenerator`：只产出
  候选意图、不自动注册（与 `conatus_skill` 启用前审批口径一致）
- 埋点：`intent.registered` / `intent.matched` / `intent.missed` 等；
  嵌入失败降级不抛错，失败嵌入缓存不重试
