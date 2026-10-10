# Changelog

本项目遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [未发布]

初始实现——主动告警策略引擎（检测与通知，与被动导出的
`conatus_observability` 互补）：

- `Alerting`（服务键 `'alerting'`）：订阅遥测事件流，按声明式规则判定异常，
  冷却期防告警风暴（同规则默认 5 分钟），`fire` 手动触发不经冷却，
  `alerts` 流与 `history` 可查询
- `AlertRule` / `AlertContext`：规则是数据——`name` + `severity` +
  纯函数 `condition` + `cooldown`；滑动窗口统计与定期清理，时间来源可注入
- 8 条默认规则：LLM 慢 / 极慢、工具慢 / 连续失败、Session 与当日预算超限、
  Agent 轮次超限、子 Agent 卡住
- 通知渠道（Capability Seam）：`ConsoleNotifier`（缺省）/ `WebhookNotifier`
  （Slack 兼容负载）/ `AskUserNotifier`（TTS 播报 + 口头响应）/
  `CompositeNotifier`（并行多渠道）/ `QuietHoursNotifier`（静默期，critical
  始终放行）
- `RuleParser`：JSON 配置加载规则，支持字段比较与窗口计数两种条件
