/// 场景三：定时提醒。
///
/// 链路：cron → session → agent。
/// 用户用自然语言设置每日提醒，Agent 调 `cron_add` 落一个 cron 表达式任务；
/// 时间推进到次日 7 点后手动触发 [CronRuntime.tick]，到期任务经宿主注入的
/// [CronDelivery] 投递（framing 带回任务 prompt），投递端把 prompt 交给
/// Agent 输出提醒。
library;

import 'package:conatus/conatus.dart';
import 'package:test/test.dart';

import 'helpers/scripted_llm.dart';
import 'helpers/test_harness.dart';

void main() {
  test('定时提醒：cron_add 落任务 → 时间推进 → tick 触发 → Agent 输出提醒', () async {
    final TestHarness h = await TestHarness.create(llmScript: <LlmResult>[
      callTool('c1', 'cron_add', <String, Object?>{
        'cron': '0 7 * * *',
        'prompt': '该喝水了',
      }),
      text('好的，我会每天早上 7 点提醒你喝水'),
      text('该喝水了！'),
    ]);
    addTearDown(h.dispose);

    // 可推进时钟：cron 服务与运行时共用，模拟时间前进。
    DateTime now = DateTime(2026, 9, 18, 8);
    DateTime clock() => now;

    provideCron(h.app, storage: FakeCronStorage(), clock: clock);
    provideCronTools(h.app);

    // 触发后投递：记录 framing 并把任务 prompt 交给 Agent 跑一轮。
    final List<String> deliveredFramings = <String>[];
    final List<String> deliveredReplies = <String>[];
    final CronRuntime runtime = provideCronRuntime(
      h.app,
      deliver: (String recordId, String framing) async {
        deliveredFramings.add(framing);
        final AgentTurn turn =
            await h.agent.run(h.app.cron.tasks.single.prompt);
        deliveredReplies.add(turn.reply);
        return true;
      },
      options: CronRuntimeOptions(
        clock: clock,
        // 关闭自动 tick，全部手动触发。
        firstTickDelay: const Duration(hours: 1),
        tickSeconds: 3600,
      ),
    );

    final AgentTurn first = await h.run('每天早上 7 点提醒我喝水');

    // 1) cron 任务被创建，表达式正确。
    expect(first.reply, contains('提醒'));
    final List<CronTask> tasks = h.app.cron.tasks;
    expect(tasks, hasLength(1));
    expect(tasks.single.cron, '0 7 * * *');

    // 2) 时间推进到次日 7 点，手动 tick 触发投递。
    now = DateTime(2026, 9, 19, 7);
    await runtime.tick();

    // 3) deliver 收到 framing（含固定前缀与任务 prompt）。
    expect(deliveredFramings, hasLength(1));
    expect(deliveredFramings.single, contains('[cron]'));
    expect(deliveredFramings.single, contains('该喝水了'));

    // 4) 投递端把 prompt 交给 Agent，输出了提醒。
    expect(deliveredReplies, hasLength(1));
    expect(deliveredReplies.single, contains('喝水'));

    // 5) 会话日志记录了任务的创建与触发。
    expect(
      h.session.events.any((SessionEvent e) =>
          e.type.contains('cron') || e.type == kToolResultEvent),
      isTrue,
    );
  }, timeout: const Timeout(Duration(seconds: 30)));
}

/// 内存 cron 存储：任务快照与历史都留在内存。
class FakeCronStorage implements CronStorage {
  CronStorageSnapshot snapshot = const CronStorageSnapshot();
  final List<Map<String, Object?>> history = <Map<String, Object?>>[];

  @override
  CronStorageSnapshot loadTasks() => snapshot;

  @override
  void saveTasks({
    required List<Map<String, Object?>> tasks,
    required Map<String, CronRunStamp> runStamps,
    required Map<String, bool> overrides,
  }) {
    snapshot = CronStorageSnapshot(
      dynamicTasks: tasks,
      runStamps: runStamps,
      overrides: overrides,
    );
  }

  @override
  List<Map<String, Object?>> loadHistory() => List<Map<String, Object?>>.of(history);

  @override
  void saveHistory(List<Map<String, Object?>> records) {
    history
      ..clear()
      ..addAll(records);
  }
}
