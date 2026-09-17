# conatus_alerting

> ⚠️ **实验性**：本包处于早期探索阶段，API 可能在没有 major 版本号变更的情况下
> 发生破坏性改动，请勿在生产环境依赖它。不进 `conatus` 伞包（`publish_to: none`），
> 使用方需显式依赖。

conatus 的告警能力：**当运行时出现异常时，主动告诉用户，而不是等用户问。**
`conatus_observability` 负责**收集和导出**（被动数据管道）；本包负责**检测和通知**
（主动策略引擎）：订阅遥测事件流，用声明式规则判断「什么不对劲」，必要时通过
控制台 / Webhook / 语音主动通知。

智能音箱场景下，用户不在屏幕前，很多异常不会主动发现——Alerting 让 Agent 能主动播报：
LLM 调用慢（「这个操作有点慢，我还在等」）、工具连续失败（「试了几次都不行，要换个
方法吗？」）、成本超预算（「今天的用量有点多，要继续吗？」）、Agent 轮次超限（「需要
更多步骤，继续吗？」）。

## 用法

```dart
provideTelemetry(app);          // telemetry 必需
provideAlerting(app);           // 默认规则 + 控制台通知（服务键 'alerting'）

// 自定义规则 / 通知渠道
provideAlerting(
  app,
  notifier: CompositeNotifier(<AlertNotifier>[
    ConsoleNotifier(),
    WebhookNotifier(url: Uri.parse('https://hooks.example.com/xxx')),
  ]),
  rules: <AlertRule>[
    AlertRule(
      name: 'llm-very-slow',
      severity: AlertSeverity.critical,
      condition: (event, ctx) =>
          event.name == 'llm.request' &&
          (event.data['durationMs'] as int? ?? 0) > 60000,
      cooldown: const Duration(minutes: 10),
    ),
  ],
);

// 语音场景：TTS 播报 + 用户口头响应
provideAlerting(app, notifier: AskUserNotifier(
  askUser: app.require<AskUser>('askUser'),
  tts: app.require<TtsService>('tts'),
  sink: audioSink,
  onUserAccepted: (alert) { /* 用户同意，触发后续动作 */ },
));

// 从 JSON 配置文件加载规则
final rules = RuleParser.parse(jsonDecode(
  File('alerts.json').readAsStringSync()) as Map<String, Object?>);
provideAlerting(app, rules: rules);
```

## 核心类型

- `Alert` / `AlertSeverity`（info / warning / critical）：一条告警，含触发事件、
  关联 `sessionId` / `goalId`（从事件 data 提取）、口语化 `summary`、JSON 往返。
- `AlertRule`：**规则是数据**——`name`（唯一）+ `severity` + 纯函数 `condition` +
  `cooldown`（同规则冷却期内只触发一次，默认 5 分钟）。
- `AlertContext`：滑动窗口统计（`record` / `countInWindow`）+ 冷却状态
  （`isCoolingDown` / `markFired`）+ 定期 `prune`；时间来源可注入（测试用）。
- `Alerting`（服务键 `'alerting'`）：`addRule` / `removeRule` / `fire`（手动触发，
  不经过冷却）/ `resolve` / `activeAlerts` / `history` / `alerts` 流。

## 默认规则集（8 条）

| 规则 | 条件 | 严重级别 | 冷却期 |
|------|------|----------|--------|
| `llm-slow` | LLM 调用 > 30 秒 | warning | 5 分钟 |
| `llm-very-slow` | LLM 调用 > 60 秒 | critical | 10 分钟 |
| `tool-slow` | 工具调用 > 10 秒 | warning | 5 分钟 |
| `tool-failures` | 1 分钟内工具失败 > 5 次 | critical | 5 分钟 |
| `session-budget` | Session 成本 > \$1 | warning | 30 分钟 |
| `daily-budget` | 当日成本 > \$10 | critical | 1 小时 |
| `agent-loop` | Agent 轮次超过 20 步 | warning | 5 分钟 |
| `subagent-stuck` | 子 Agent 超时（暂缓，只记录） | warning | 5 分钟 |

事件名对齐 conatus 实际遥测词汇（`conatus_agent` 的 `telemetry.dart`）：
`llm.request` / `tool.called` / `tool.failed` / `agent.round`；`cost.recorded` /
`agent.round.exceeded` 为预留事件名，由上层埋点触发。

## 通知渠道（Capability Seam）

| 渠道 | 说明 |
|------|------|
| `ConsoleNotifier`（缺省） | stderr 一行一条，`[WARN] rule: summary`，可带时间戳 |
| `WebhookNotifier` | Slack 兼容负载（`text` + `attachments`），`http.Client` 可注入 Mock |
| `AskUserNotifier` | 语音播报（TTS + sink），或降级为 `askUser.ask` 文本提问；口头响应触发 `onUserAccepted` / `onUserRejected` |
| `CompositeNotifier` | 并行通知多个渠道，任一失败不影响其他 |
| `QuietHoursNotifier` | 静默期（可跨午夜）内只记录不播报，**critical 始终放行** |

## 规则配置（JSON）

```json
{
  "rules": [
    {
      "name": "llm-slow",
      "severity": "warning",
      "cooldown": 300,
      "condition": { "event": "llm.request", "field": "durationMs", "operator": ">", "value": 30000 }
    },
    {
      "name": "tool-failures",
      "severity": "critical",
      "condition": { "event": "tool.failed", "window": 60, "count": 5, "operator": ">" }
    }
  ]
}
```

`RuleParser` 支持两种条件：字段比较（`field` + `operator` + `value`）与窗口计数
（`window` + `count`）。

## 注意与限制

- **告警不阻塞主流程**：通知失败只记录到 stderr，不抛异常。
- **规则条件是纯函数**：不修改外部状态；单条规则抛异常不影响其他规则（`Alerting`
  隔离并记录）。
- **冷却期防告警风暴**：默认 5 分钟，可配置；手动 `fire` 不经过冷却。
- **窗口计数定期清理**：默认 1 小时，防止内存增长。
- **静默期不阻断 critical**：critical 告警始终播报。
- **与 observability 解耦**：只依赖 `Telemetry` 接口（`conatus_agent`），不依赖
  具体导出器实现；`subagent-stuck` 的超时判断暂缓（事件只记录），由上层定时器完成。
- 依赖方向：`conatus_alerting → conatus_agent / conatus_tts / conatus_foundation`，
  反向不成立；`conatus_observability` 不依赖本包。
- 设计细节见 `.handoffs/HANDOFF-11.md`。
