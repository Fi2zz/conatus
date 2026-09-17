import 'dart:io';

import 'package:conatus_cron/conatus_cron.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('任务 CRUD', () {
    test('动态任务：缺省 id 生成 + 会话绑定，显式 sessionId 优先', () {
      final built = buildService();
      final CronTaskView bound = built.service.addDynamicTask(
          <String, Object?>{'prompt': 'ping', 'every': 600},
          callerSessionId: 'sess-1');
      expect(kCronTaskIdPattern.hasMatch(bound.id), isTrue);
      expect(bound.sessionId, 'sess-1');
      expect(bound.schedule, <String, Object?>{'everySeconds': 600});
      expect(bound.enabled, isTrue);
      expect(bound.origin, CronTaskOrigin.dynamic);

      final CronTaskView explicit = built.service
          .addDynamicTask(<String, Object?>{
        'prompt': 'pong',
        'every': 600,
        'sessionId': 'sess-2'
      }, callerSessionId: 'sess-1');
      expect(explicit.sessionId, 'sess-2');
    });

    test('重复 id 与非法输入抛 CronException', () {
      final built = buildService();
      built.service.addDynamicTask(
          <String, Object?>{'id': 'dupe', 'prompt': 'a', 'every': 600});
      expect(
        () => built.service.addDynamicTask(
            <String, Object?>{'id': 'dupe', 'prompt': 'b', 'every': 600}),
        throwsA(isA<CronException>().having(
            (CronException e) => e.code, 'code', CronErrorCode.duplicateId)),
      );
      expect(
        () => built.service
            .addDynamicTask(<String, Object?>{'prompt': 'a', 'every': 5}),
        throwsA(isA<CronException>().having(
            (CronException e) => e.code, 'code', CronErrorCode.invalidTask)),
      );
    });

    test('listTasks 覆盖配置与动态任务', () {
      final built = buildService(configTasks: <Map<String, Object?>>[
        <String, Object?>{'id': 'cfg', 'prompt': '配置任务', 'daily': '08:00'},
      ]);
      built.service.addDynamicTask(
          <String, Object?>{'id': 'dyn', 'prompt': '动态任务', 'every': 600});
      final List<CronTaskView> views = built.service.listTasks();
      expect(views.map((CronTaskView view) => view.id), <String>['cfg', 'dyn']);
      expect(views.first.origin, CronTaskOrigin.config);
      expect(views.first.schedule, <String, Object?>{'daily': '08:00'});
    });

    test('update：仅 prompt 原地更新；规则替换清空运行戳', () {
      final built = buildService();
      built.service.addDynamicTask(
          <String, Object?>{'id': 't', 'prompt': '旧', 'every': 600});
      fireOnce(built.service, 't', base);
      final CronTask task = built.service.findTask('t')!;
      expect(task.lastRunAt, base);

      final CronTaskView promptOnly = built.service
          .updateDynamicTask('t', <String, Object?>{'prompt': '新'});
      expect(promptOnly.prompt, '新');
      expect(built.service.findTask('t')!.lastRunAt, base,
          reason: '仅改 prompt 不重置运行戳');

      final CronTaskView replaced = built.service
          .updateDynamicTask('t', <String, Object?>{'daily': '09:30'});
      expect(replaced.schedule, <String, Object?>{'daily': '09:30'});
      final CronTask after = built.service.findTask('t')!;
      expect(after.every, isNull);
      expect(after.lastRunAt, isNull);
      expect(after.cronNext, isNull);
    });

    test('update：patch 携带两个规则或非法规则时拒绝', () {
      final built = buildService();
      built.service.addDynamicTask(
          <String, Object?>{'id': 't', 'prompt': 'a', 'every': 600});
      expect(
        () => built.service.updateDynamicTask(
            't', <String, Object?>{'daily': '09:00', 'every': 600}),
        throwsA(isA<CronException>().having(
            (CronException e) => e.code, 'code', CronErrorCode.invalidTask)),
      );
      expect(
        () =>
            built.service.updateDynamicTask('t', <String, Object?>{'every': 5}),
        throwsA(isA<CronException>().having(
            (CronException e) => e.code, 'code', CronErrorCode.invalidTask)),
      );
    });

    test('config 任务保护：update / remove 拒绝，add 撞 id 报重复', () {
      final built = buildService(configTasks: <Map<String, Object?>>[
        <String, Object?>{'id': 'cfg', 'prompt': 'a', 'daily': '08:00'},
      ]);
      expect(
        () => built.service
            .updateDynamicTask('cfg', <String, Object?>{'prompt': 'b'}),
        throwsA(isA<CronException>().having(
            (CronException e) => e.code, 'code', CronErrorCode.configTask)),
      );
      expect(
        () => built.service.removeDynamicTask('cfg'),
        throwsA(isA<CronException>().having(
            (CronException e) => e.code, 'code', CronErrorCode.configTask)),
      );
      expect(
        () => built.service.addDynamicTask(
            <String, Object?>{'id': 'cfg', 'prompt': 'b', 'every': 600}),
        throwsA(isA<CronException>().having(
            (CronException e) => e.code, 'code', CronErrorCode.duplicateId)),
      );
      expect(
        () => built.service.removeDynamicTask('missing'),
        throwsA(isA<CronException>().having(
            (CronException e) => e.code, 'code', CronErrorCode.notFound)),
      );
    });

    test('remove 动态任务并落盘', () {
      final built = buildService();
      built.service.addDynamicTask(
          <String, Object?>{'id': 't', 'prompt': 'a', 'every': 600});
      built.service.removeDynamicTask('t');
      expect(built.service.listTasks(), isEmpty);
      final File tasksFile = File('${built.dir.path}/cron-tasks.json');
      expect(tasksFile.readAsStringSync(), contains('"tasks": []'));
    });

    test('enabledOverride 与声明值一致时归 null', () {
      final built = buildService(configTasks: <Map<String, Object?>>[
        <String, Object?>{
          'id': 'off',
          'prompt': 'a',
          'daily': '08:00',
          'enabled': false
        },
      ]);
      built.service.addDynamicTask(
          <String, Object?>{'id': 'on', 'prompt': 'a', 'every': 600});

      final CronTaskView off = built.service.setEnabled('on', false);
      expect(off.enabled, isFalse);
      expect(built.service.findTask('on')!.enabledOverride, isFalse);

      final CronTaskView back = built.service.setEnabled('on', true);
      expect(back.enabled, isTrue);
      expect(built.service.findTask('on')!.enabledOverride, isNull,
          reason: '覆盖值与声明值一致时归 null');

      final CronTaskView lifted = built.service.setEnabled('off', true);
      expect(lifted.enabled, isTrue);
      expect(built.service.findTask('off')!.enabledOverride, isTrue);
    });

    test('启动跳过损坏任务并告警', () {
      final Directory dir =
          Directory.systemTemp.createTempSync('conatus-cron-test-');
      addTearDown(() => dir.deleteSync(recursive: true));
      File('${dir.path}/cron-tasks.json').writeAsStringSync(
          '{"version":1,"tasks":[{"id":"bad"},{"id":"good","prompt":"a","every":600}],"runs":{},"overrides":{}}');
      final List<String> warnings = <String>[];
      final CronService service = CronService(
        storage: JsonCronStorage(
          tasksPath: '${dir.path}/cron-tasks.json',
          historyPath: '${dir.path}/cron-history.jsonl',
          onWarning: warnings.add,
        ),
        onWarning: warnings.add,
      );
      expect(service.listTasks().map((CronTaskView view) => view.id),
          <String>['good']);
      expect(warnings.join('\n'), contains('skipping stored task'));
    });
  });
}
