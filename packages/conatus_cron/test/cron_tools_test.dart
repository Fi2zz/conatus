import 'dart:io';

import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_cron/conatus_cron.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

final DateTime base = DateTime(2026, 9, 16, 10);

({Context ctx, CronService service}) buildTools({
  List<Map<String, Object?>> configTasks = const <Map<String, Object?>>[],
}) {
  final Context ctx = Context.root();
  addTearDown(ctx.dispose);
  final Directory dir =
      Directory.systemTemp.createTempSync('conatus-cron-tools-');
  addTearDown(() => dir.deleteSync(recursive: true));
  final CronStorage storage = CronStorage(
    tasksPath: '${dir.path}/cron-tasks.json',
    historyPath: '${dir.path}/cron-history.jsonl',
  );
  provideTools(ctx);
  final CronService service = provideCron(
    ctx,
    storage: storage,
    configTasks: configTasks,
    clock: () => base,
  );
  provideCronTools(ctx);
  return (ctx: ctx, service: service);
}

Future<ToolResult> call(Context ctx, String name,
        [Map<String, Object?> arguments = const <String, Object?>{}]) =>
    ctx.tools.call(ToolCall(name: name, arguments: arguments));

void main() {
  test('注册五个工具并随上下文释放注销', () {
    final Context ctx = Context.root();
    final Directory dir =
        Directory.systemTemp.createTempSync('conatus-cron-tools-');
    addTearDown(() => dir.deleteSync(recursive: true));
    provideTools(ctx);
    provideCron(
      ctx,
      storage: CronStorage(
        tasksPath: '${dir.path}/cron-tasks.json',
        historyPath: '${dir.path}/cron-history.jsonl',
      ),
    );
    final List<Tool> tools = provideCronTools(ctx);
    expect(tools.map((Tool tool) => tool.name), <String>[
      'cron_list',
      'cron_history',
      'cron_add',
      'cron_update',
      'cron_remove',
    ]);
    final ToolRegistry registry = ctx.tools;
    expect(registry.names, contains('cron_add'));
    ctx.dispose();
    expect(registry.names, isEmpty);
  });

  group('cron_add', () {
    test('参数校验错误返回 invalid-task', () async {
      final ({Context ctx, CronService service}) built = buildTools();
      final List<Map<String, Object?>> cases = <Map<String, Object?>>[
        <String, Object?>{'prompt': 'a', 'every': 600, 'daily': '09:00'},
        <String, Object?>{'prompt': 'a', 'every': 5},
        <String, Object?>{'prompt': 'a', 'cron': 'not-a-cron'},
        <String, Object?>{'prompt': 'a', 'daily': '9:00'},
        <String, Object?>{'prompt': 'a', 'at': 'bogus'},
        <String, Object?>{'prompt': '   ', 'every': 600},
        <String, Object?>{'prompt': 'a', 'every': 600, 'id': 'bad id'},
      ];
      for (final Map<String, Object?> args in cases) {
        final ToolResult result = await call(built.ctx, 'cron_add', args);
        expect(result.isError, isTrue, reason: '$args');
        expect(result.error?.code, CronErrorCode.invalidTask, reason: '$args');
      }
      expect(built.service.listTasks(), isEmpty);
    });

    test('缺必填参数由注册表拦截为 INVALID_ARGS', () async {
      final ({Context ctx, CronService service}) built = buildTools();
      final ToolResult result = await call(built.ctx, 'cron_add');
      expect(result.error?.code, 'INVALID_ARGS');
    });

    test('成功路径：生成 id、返回视图并持久化', () async {
      final ({Context ctx, CronService service}) built = buildTools();
      final ToolResult result = await call(built.ctx, 'cron_add', <String, Object?>{
        'prompt': '每周一晨报',
        'cron': '0 9 * * 1',
      });
      expect(result.isError, isFalse, reason: result.content);
      final Map<String, Object?> view = result.value! as Map<String, Object?>;
      expect(kCronTaskIdPattern.hasMatch(view['id']! as String), isTrue);
      expect(view['schedule'], <String, Object?>{'cron': '0 9 * * 1'});
      expect(view['nextRunAt'], isNotNull);
      expect(built.service.listTasks(), hasLength(1));
    });

    test('会话绑定：工具构造时的调用方会话与显式 session_id', () async {
      final ({Context ctx, CronService service}) built = buildTools();
      final CronAddTool bound = CronAddTool(
          service: built.service, callerSessionId: 'sess-1');
      final ToolResult viaBound = await bound.call(const ToolContext(ToolCall(
          name: 'cron_add',
          arguments: <String, Object?>{'prompt': 'a', 'every': 600})));
      expect((viaBound.value! as Map<String, Object?>)['sessionId'], 'sess-1');

      final ToolResult explicit = await bound.call(const ToolContext(ToolCall(
          name: 'cron_add',
          arguments: <String, Object?>{
            'prompt': 'b',
            'every': 600,
            'session_id': 'sess-2',
          })));
      expect((explicit.value! as Map<String, Object?>)['sessionId'], 'sess-2',
          reason: '显式 session_id 优先于调用方会话');

      final ToolResult injected = await CronAddTool(service: built.service)
          .call(const ToolContext(ToolCall(
              name: 'cron_add',
              arguments: <String, Object?>{
            'prompt': 'c',
            'every': 600,
            '_session_id': 'sess-9',
          })));
      expect((injected.value! as Map<String, Object?>)['sessionId'], 'sess-9',
          reason: '宿主注入的 _session_id 作为回退通道');
    });
  });

  group('cron_update / cron_remove', () {
    test('动态任务成功路径', () async {
      final ({Context ctx, CronService service}) built = buildTools();
      await call(built.ctx, 'cron_add', <String, Object?>{
        'id': 'task-1',
        'prompt': '旧内容',
        'every': 600,
      });

      final ToolResult updated =
          await call(built.ctx, 'cron_update', <String, Object?>{
        'id': 'task-1',
        'prompt': '新内容',
        'daily': '08:30',
      });
      expect(updated.isError, isFalse, reason: updated.content);
      final Map<String, Object?> view = updated.value! as Map<String, Object?>;
      expect(view['prompt'], '新内容');
      expect(view['schedule'], <String, Object?>{'daily': '08:30'});

      final ToolResult removed =
          await call(built.ctx, 'cron_remove', <String, Object?>{'id': 'task-1'});
      expect(removed.isError, isFalse);
      expect((removed.value! as Map<String, Object?>)['removed'], 'task-1');
      expect(built.service.listTasks(), isEmpty);
    });

    test('config 任务拒绝编辑与删除', () async {
      final ({Context ctx, CronService service}) built = buildTools(
        configTasks: <Map<String, Object?>>[
          <String, Object?>{
            'id': 'cfg',
            'prompt': '配置任务',
            'daily': '08:00',
          },
        ],
      );
      final ToolResult updated =
          await call(built.ctx, 'cron_update', <String, Object?>{
        'id': 'cfg',
        'prompt': '改动',
      });
      expect(updated.error?.code, CronErrorCode.configTask);

      final ToolResult removed =
          await call(built.ctx, 'cron_remove', <String, Object?>{'id': 'cfg'});
      expect(removed.error?.code, CronErrorCode.configTask);
      expect(built.service.listTasks(), hasLength(1));

      final ToolResult missing =
          await call(built.ctx, 'cron_remove', <String, Object?>{'id': 'nope'});
      expect(missing.error?.code, CronErrorCode.notFound);
    });
  });

  group('cron_list / cron_history', () {
    test('列表包含配置与动态任务及生效状态', () async {
      final ({Context ctx, CronService service}) built = buildTools(
        configTasks: <Map<String, Object?>>[
          <String, Object?>{
            'id': 'cfg',
            'prompt': '配置任务',
            'daily': '08:00',
          },
        ],
      );
      await call(built.ctx, 'cron_add', <String, Object?>{
        'id': 'dyn',
        'prompt': '动态任务',
        'every': 600,
      });
      built.service.setEnabled('dyn', false);

      final ToolResult listed = await call(built.ctx, 'cron_list');
      expect(listed.isError, isFalse);
      final List<Object?> views = listed.value! as List<Object?>;
      expect(views, hasLength(2));
      final Map<String, Object?> dyn = views.last! as Map<String, Object?>;
      expect(dyn['enabled'], isFalse);
      expect(dyn['origin'], 'dynamic');
      expect(dyn['schedule'], <String, Object?>{'everySeconds': 600});
    });

    test('历史返回运行记录', () async {
      final ({Context ctx, CronService service}) built = buildTools();
      await call(built.ctx, 'cron_add', <String, Object?>{
        'id': 't',
        'prompt': 'a',
        'every': 600,
      });
      final CronRecordRef ref = built.service.allocateRecordRef(base);
      built.service.commitFire(ref: ref, taskId: 't', slot: base, firedAt: base);
      built.service.finishRun(ref.id, ok: true, excerpt: '完成');

      final ToolResult history = await call(built.ctx, 'cron_history');
      expect(history.isError, isFalse);
      final List<Object?> records = history.value! as List<Object?>;
      expect(records, hasLength(1));
      final Map<String, Object?> record = records.single! as Map<String, Object?>;
      expect(record['status'], CronRunStatus.completed);
      expect(record['taskId'], 't');
      expect(record['excerpt'], '完成');
    });
  });
}
