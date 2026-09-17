/// conatus_alerting：告警能力（实验性）。
///
/// 本包处于早期探索阶段，API 可能在没有 major 版本号变更的情况下发生
/// 破坏性改动。请勿在生产环境依赖它。
///
/// `conatus_observability` 负责**收集和导出**（被动），本包负责**检测和通知**
/// （主动）：订阅 [Telemetry] 事件流，用声明式规则判断「什么不对劲」，必要时
/// 通过控制台 / Webhook / 语音主动告诉用户，而不是等用户问。
///
/// 设计要点：
///
/// - **规则是数据**：`AlertRule` 用声明式条件定义，可从 JSON 加载
///   （[RuleParser]），不从代码硬编码；
/// - **通知渠道是 Seam**：`AlertNotifier` 可替换为控制台 / Webhook / 语音 /
///   复合渠道；
/// - **冷却期防告警风暴**：同一条规则在冷却期内只触发一次（默认 5 分钟）；
/// - **告警不阻塞主流程**：通知失败只记录到 stderr，不抛异常；
/// - **与 observability 解耦**：只依赖 [Telemetry] 接口，不依赖具体导出器。
///
/// 智能音箱场景下，告警通过 TTS 播报（[AskUserNotifier] 组合 `askUser` /
/// `tts` seam），用户可口头响应（`onUserAccepted` / `onUserRejected`），
/// 静默期用 [QuietHoursNotifier] 包裹（critical 始终播报）。
library;

export 'src/alert.dart' show Alert, AlertSeverity;
export 'src/alerting.dart'
    show Alerting, AlertingContext, AlertingImpl, provideAlerting;
export 'src/notifiers/ask_user_notifier.dart' show AskUserNotifier;
export 'src/notifiers/composite_notifier.dart' show CompositeNotifier;
export 'src/notifiers/console_notifier.dart' show ConsoleNotifier;
export 'src/notifiers/notifier.dart' show AlertNotifier;
export 'src/notifiers/quiet_hours_notifier.dart' show QuietHoursNotifier;
export 'src/notifiers/webhook_notifier.dart' show WebhookNotifier;
export 'src/rule.dart' show AlertContext, AlertRule;
export 'src/rules/default_rules.dart' show defaultAlertRules;
export 'src/rules/rule_parser.dart' show RuleParser;
