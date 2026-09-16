import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

Map<String, Object?> createPayload({
  String id = 'schedule-1',
  String prompt = '到点了',
  required DateTime scheduledAt,
}) =>
    <String, Object?>{
      'version': 1,
      'operation': 'create',
      'schedule': <String, Object?>{
        'id': id,
        'kind': 'at',
        'prompt': prompt,
        'scheduledAt': formatUtcInstant(scheduledAt),
      },
    };

int changeCount(Session session) => session.ownEvents
    .where((SessionEvent event) => event.type == kScheduleChangeEvent)
    .length;

Future<void> settle() =>
    Future<void>.delayed(const Duration(milliseconds: 250));

void main() {
  test('到期的提醒被交付，并写入一条派发事件', () async {
    final Session session = Session(id: 's1');
    addTearDown(session.close);
    session.append(kScheduleChangeEvent,
        data: createPayload(
            scheduledAt:
                DateTime.now().toUtc().add(const Duration(milliseconds: 60))));
    final List<String> delivered = <String>[];
    final ScheduleRuntime runtime = ScheduleRuntime(
      schedule: SessionSchedule(session: session),
      deliver: (String text) async {
        delivered.add(text);
        return true;
      },
    );
    addTearDown(runtime.dispose);
    runtime.requestDrive();
    await settle();

    expect(delivered, hasLength(1));
    expect(delivered.single, contains('reminder_prompt_json: "到点了"'));
    expect(foldScheduleEvents(session.ownEvents).active, isEmpty);
    expect(changeCount(session), 2);

    await settle();
    expect(delivered, hasLength(1), reason: '已派发的记录不应再次交付');
  });

  test('投递被拒绝时不写派发事件，记录保持活动', () async {
    final Session session = Session(id: 's1');
    addTearDown(session.close);
    session.append(kScheduleChangeEvent,
        data: createPayload(
            scheduledAt:
                DateTime.now().toUtc().add(const Duration(milliseconds: 60))));
    final ScheduleRuntime runtime = ScheduleRuntime(
      schedule: SessionSchedule(session: session),
      deliver: (String text) async => false,
    );
    addTearDown(runtime.dispose);
    runtime.requestDrive();
    await settle();

    expect(changeCount(session), 1);
    expect(foldScheduleEvents(session.ownEvents).active, hasLength(1));
  });

  test('尚未到期的提醒不会被提前交付', () async {
    final Session session = Session(id: 's1');
    addTearDown(session.close);
    session.append(kScheduleChangeEvent,
        data: createPayload(
            scheduledAt: DateTime.now().toUtc().add(const Duration(hours: 1))));
    final List<String> delivered = <String>[];
    final ScheduleRuntime runtime = ScheduleRuntime(
      schedule: SessionSchedule(session: session),
      deliver: (String text) async {
        delivered.add(text);
        return true;
      },
    );
    addTearDown(runtime.dispose);
    runtime.requestDrive();
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(delivered, isEmpty);
    expect(changeCount(session), 1);
  });

  test('释放时取消等待中的定时器', () async {
    final Session session = Session(id: 's1');
    addTearDown(session.close);
    session.append(kScheduleChangeEvent,
        data: createPayload(
            scheduledAt:
                DateTime.now().toUtc().add(const Duration(milliseconds: 80))));
    final List<String> delivered = <String>[];
    final ScheduleRuntime runtime = ScheduleRuntime(
      schedule: SessionSchedule(session: session),
      deliver: (String text) async {
        delivered.add(text);
        return true;
      },
    );
    runtime.requestDrive();
    await runtime.dispose();
    await settle();
    expect(delivered, isEmpty);
    expect(changeCount(session), 1);
  });

  test('固定间隔提醒按批次交付且只写一次决策时点', () async {
    final Session session = Session(id: 's1');
    addTearDown(session.close);
    session.append(kScheduleChangeEvent, data: <String, Object?>{
      'version': 1,
      'operation': 'create',
      'schedule': <String, Object?>{
        'id': 'schedule-1',
        'kind': 'every',
        'prompt': '检查构建',
        'everySeconds': 300,
        'scheduledAt': formatUtcInstant(
            DateTime.now().toUtc().subtract(const Duration(minutes: 1))),
      },
    });
    final List<String> delivered = <String>[];
    final ScheduleRuntime runtime = ScheduleRuntime(
      schedule: SessionSchedule(session: session),
      deliver: (String text) async {
        delivered.add(text);
        return true;
      },
    );
    addTearDown(runtime.dispose);
    runtime.requestDrive();
    await settle();

    expect(delivered, hasLength(1));
    expect(delivered.single, contains('[SCHEDULE REMINDER BATCH]'));
    expect(delivered.single, contains('"reminder_prompt":"检查构建"'));
    final ScheduleFold folded = foldScheduleEvents(session.ownEvents);
    expect(folded.active.single.id, 'schedule-1');
    expect(folded.active.single.scheduledAt.isAfter(DateTime.now().toUtc()),
        isTrue);
  });
}
