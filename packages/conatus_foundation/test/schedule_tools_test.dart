import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

final DateTime base = DateTime.utc(2026, 8, 6, 12);

({Context ctx, Session session}) build() {
  final Context ctx = Context.root();
  addTearDown(ctx.dispose);
  final Session session = Session(id: 's1');
  addTearDown(session.close);
  provideTools(ctx);
  provideSessionSchedule(ctx, session: session, clock: () => base);
  provideScheduleTools(ctx);
  return (ctx: ctx, session: session);
}

Future<ToolResult> callCreate(Context ctx, Map<String, Object?> args) =>
    ctx.tools.call(ToolCall(name: 'schedule_create', arguments: args));

void main() {
  group('工具注册与形状', () {
    test('注册三个工具并按上下文释放注销', () {
      final Context ctx = Context.root();
      final Session session = Session(id: 's1');
      provideTools(ctx);
      provideSessionSchedule(ctx, session: session, clock: () => base);
      final List<Tool> tools = provideScheduleTools(ctx);
      final ToolRegistry registry = ctx.tools;
      expect(tools.map((Tool tool) => tool.name),
          <String>['schedule_create', 'schedule_list', 'schedule_delete']);
      expect(registry.names, contains('schedule_create'));
      ctx.dispose();
      expect(registry.names, isEmpty);
      session.close();
    });

    test('at 参数是字符串或对象的二选一联合', () {
      final Context ctx = Context.root();
      addTearDown(ctx.dispose);
      final Session session = Session(id: 's1');
      addTearDown(session.close);
      provideTools(ctx);
      provideSessionSchedule(ctx, session: session, clock: () => base);
      final List<Tool> tools = provideScheduleTools(ctx);
      final Tool create =
          tools.firstWhere((Tool tool) => tool.name == 'schedule_create');
      final Map<String, Object?> schema = create.toSchema();
      final Map<String, Object?> properties = (schema['parameters']!
          as Map<String, Object?>)['properties']! as Map<String, Object?>;
      final List<Object?> union = (properties['at']!
          as Map<String, Object?>)['oneOf']! as List<Object?>;
      expect(union, hasLength(2));
      expect((union.first! as Map<String, Object?>)['type'], 'string');
      expect((union.last! as Map<String, Object?>)['type'], 'object');
    });
  });

  group('创建参数校验', () {
    test('选择器与内容违规的错误码', () async {
      final ({Context ctx, Session session}) built = build();
      final List<(Map<String, Object?>, String)> cases =
          <(Map<String, Object?>, String)>[
        (<String, Object?>{'prompt': 'a'}, ScheduleErrorCode.invalidSelector),
        (
          <String, Object?>{
            'prompt': 'a',
            'after_seconds': 60,
            'every_seconds': 300
          },
          ScheduleErrorCode.invalidSelector
        ),
        (
          <String, Object?>{'prompt': 'a', 'after_seconds': 60, 'extra': 1},
          ScheduleErrorCode.invalidSelector
        ),
        (
          <String, Object?>{'prompt': '   ', 'after_seconds': 60},
          ScheduleErrorCode.invalidPrompt
        ),
        (
          <String, Object?>{'prompt': 'a', 'after_seconds': 0},
          ScheduleErrorCode.invalidRule
        ),
        (
          <String, Object?>{'prompt': 'a', 'after_seconds': 1.5},
          ScheduleErrorCode.invalidRule
        ),
        (
          <String, Object?>{'prompt': 'a', 'every_seconds': 299},
          ScheduleErrorCode.frequencyTooHigh
        ),
        (
          <String, Object?>{'prompt': 'a', 'at': '2026-08-06T12:00:00'},
          ScheduleErrorCode.invalidRule
        ),
      ];
      for (final (Map<String, Object?> args, String code) in cases) {
        final ToolResult result = await callCreate(built.ctx, args);
        expect(result.isError, isTrue, reason: '$args');
        expect(result.error?.code, code, reason: '$args');
      }
      expect(built.session.length, 0);
    });

    test('创建成功返回规范 JSON 与视图字段', () async {
      final ({Context ctx, Session session}) built = build();
      final ToolResult result = await callCreate(built.ctx, <String, Object?>{
        'prompt': '跟进迁移',
        'after_seconds': 600,
      });
      expect(result.isError, isFalse);
      final Map<String, Object?> value = result.value! as Map<String, Object?>;
      expect(value['id'], 'schedule-1');
      expect(value['kind'], 'after');
      expect(value['afterSeconds'], 600);
      expect(value['state'], 'scheduled');
      expect(value['deliveryMode'], kScheduleDeliveryMode);
      expect(value['scheduledAt'], '2026-08-06T12:10:00.000Z');
    });

    test('at 对象形态只持久化 UTC 瞬时', () async {
      final ({Context ctx, Session session}) built = build();
      final ToolResult result = await callCreate(built.ctx, <String, Object?>{
        'prompt': '跟进迁移',
        'at': <String, Object?>{
          'date': '2026-08-06',
          'time': '22:00:00',
          'time_zone': 'Asia/Shanghai',
        },
      });
      expect(result.isError, isFalse, reason: result.content);
      expect((result.value! as Map<String, Object?>)['scheduledAt'],
          '2026-08-06T14:00:00.000Z');
    });
  });

  group('列表与删除', () {
    test('列表按创建顺序返回，删除未找到返回 deleted false', () async {
      final ({Context ctx, Session session}) built = build();
      await callCreate(
          built.ctx, <String, Object?>{'prompt': 'a', 'after_seconds': 60});
      await callCreate(
          built.ctx, <String, Object?>{'prompt': 'b', 'after_seconds': 120});

      final ToolResult listed =
          await built.ctx.tools.call(const ToolCall(name: 'schedule_list'));
      expect(listed.isError, isFalse);
      final List<Object?> views = listed.value! as List<Object?>;
      expect(views.map((Object? v) => (v! as Map<String, Object?>)['id']),
          <String>['schedule-1', 'schedule-2']);

      final ToolResult missing = await built.ctx.tools.call(const ToolCall(
          name: 'schedule_delete',
          arguments: <String, Object?>{'id': 'schedule-9'}));
      expect(missing.isError, isFalse);
      expect((missing.value! as Map<String, Object?>)['deleted'], isFalse);
      expect((missing.value! as Map<String, Object?>)['code'],
          ScheduleErrorCode.notFound);

      final ToolResult deleted = await built.ctx.tools.call(const ToolCall(
          name: 'schedule_delete',
          arguments: <String, Object?>{'id': 'schedule-1'}));
      expect((deleted.value! as Map<String, Object?>)['deleted'], isTrue);
      expect(
          (await built.ctx.tools.call(const ToolCall(name: 'schedule_list')))
              .value,
          hasLength(1));
    });

    test('删除标识带空白时返回 invalid_rule', () async {
      final ({Context ctx, Session session}) built = build();
      final ToolResult result = await built.ctx.tools.call(const ToolCall(
          name: 'schedule_delete',
          arguments: <String, Object?>{'id': ' schedule-1'}));
      expect(result.error?.code, ScheduleErrorCode.invalidRule);
    });
  });
}
