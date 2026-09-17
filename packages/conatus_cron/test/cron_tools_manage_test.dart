import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_cron/conatus_cron.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
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

      final ToolResult removed = await call(
          built.ctx, 'cron_remove', <String, Object?>{'id': 'task-1'});
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
      built.service
          .commitFire(ref: ref, taskId: 't', slot: base, firedAt: base);
      built.service.finishRun(ref.id, ok: true, excerpt: '完成');

      final ToolResult history = await call(built.ctx, 'cron_history');
      expect(history.isError, isFalse);
      final List<Object?> records = history.value! as List<Object?>;
      expect(records, hasLength(1));
      final Map<String, Object?> record =
          records.single! as Map<String, Object?>;
      expect(record['status'], CronRunStatus.completed);
      expect(record['taskId'], 't');
      expect(record['excerpt'], '完成');
    });
  });
}
