import 'dart:io';

import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_cron/conatus_cron.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  test('注册五个工具并随上下文释放注销', () {
    final Context ctx = Context.root();
    final Directory dir =
        Directory.systemTemp.createTempSync('conatus-cron-tools-');
    addTearDown(() => dir.deleteSync(recursive: true));
    provideTools(ctx);
    provideCron(
      ctx,
      storage: JsonCronStorage(
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
      final ToolResult result =
          await call(built.ctx, 'cron_add', <String, Object?>{
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
      final CronAddTool bound =
          CronAddTool(service: built.service, callerSessionId: 'sess-1');
      final ToolResult viaBound = await bound.call(const ToolContext(ToolCall(
          name: 'cron_add',
          arguments: <String, Object?>{'prompt': 'a', 'every': 600})));
      expect((viaBound.value! as Map<String, Object?>)['sessionId'], 'sess-1');

      final ToolResult explicit = await bound.call(const ToolContext(
          ToolCall(name: 'cron_add', arguments: <String, Object?>{
        'prompt': 'b',
        'every': 600,
        'session_id': 'sess-2',
      })));
      expect((explicit.value! as Map<String, Object?>)['sessionId'], 'sess-2',
          reason: '显式 session_id 优先于调用方会话');

      final ToolResult injected = await CronAddTool(service: built.service)
          .call(const ToolContext(
              ToolCall(name: 'cron_add', arguments: <String, Object?>{
        'prompt': 'c',
        'every': 600,
        '_session_id': 'sess-9',
      })));
      expect((injected.value! as Map<String, Object?>)['sessionId'], 'sess-9',
          reason: '宿主注入的 _session_id 作为回退通道');
    });
  });
}
