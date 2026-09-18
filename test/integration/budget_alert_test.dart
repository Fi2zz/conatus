/// 场景七：预算告警。
///
/// 链路：observability → alerting → 终端输出。
/// 成本记录（`cost.recorded`，当前无埋点，由测试手动 emit）超过阈值触发
/// session-budget 规则，告警经 [ConsoleNotifier] 打 `[WARN]` 到终端；冷却期内
/// 连续超阈值只触发一次；告警不阻塞后续对话。
library;

import 'package:conatus/conatus.dart';
import 'package:conatus_alerting/conatus_alerting.dart';
import 'package:test/test.dart';

import 'helpers/scripted_llm.dart';
import 'helpers/test_harness.dart';

void main() {
  test('预算告警：超阈值触发 [WARN]，冷却期内不重复，对话不受影响', () async {
    final TestHarness h = await TestHarness.create(llmScript: <LlmResult>[
      text('好的，继续执行'),
    ]);
    addTearDown(h.dispose);

    // 自定义 session-budget 规则：单次成本 > $0.01 即触发，走终端输出。
    provideAlerting(
      h.app,
      rules: const <AlertRule>[
        AlertRule(
          name: 'session-budget',
          severity: AlertSeverity.warning,
          condition: _isOverBudget,
          description: '会话成本超过 0.01 美元',
        ),
      ],
      notifier: ConsoleNotifier(writer: h.output),
      telemetry: h.telemetry,
    );

    // 1) 成本超阈值两次（冷却期内，默认 5 分钟）。
    h.telemetry.emit(
        TelemetryEvent('cost.recorded', data: <String, Object?>{'sessionCost': 0.02}));
    h.telemetry.emit(
        TelemetryEvent('cost.recorded', data: <String, Object?>{'sessionCost': 0.03}));
    await h.settle();

    // 2) 只触发一次（冷却生效），告警打到终端。
    final List<Alert> budgetAlerts = h.app.alerting.history
        .where((Alert a) => a.rule == 'session-budget')
        .toList();
    expect(budgetAlerts, hasLength(1));
    h.output.expectContains('[WARN]');
    h.output.expectContains('session-budget');

    // 3) 用户继续，对话正常收口，不受告警影响。
    final AgentTurn turn = await h.run('继续');
    expect(turn.reply, contains('继续'));
  }, timeout: const Timeout(Duration(seconds: 30)));
}

/// 单次成本事件超过阈值即触发。
bool _isOverBudget(TelemetryEvent event, AlertContext _) {
  if (event.name != 'cost.recorded') return false;
  final Object? cost = event.data['sessionCost'];
  return cost is num && cost.toDouble() > 0.01;
}
