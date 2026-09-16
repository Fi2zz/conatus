import 'dart:io';

import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_schedule/conatus_schedule.dart';
import 'package:test/test.dart';

final DateTime base = DateTime.utc(2026, 8, 6, 12);

SessionSchedule fixedClock(Session session, {SessionStore? sessions}) =>
    SessionSchedule(session: session, sessions: sessions, clock: () => base);

class FailingPersistence implements SessionPersistence {
  @override
  Future<void> append(String id, SessionEvent event) async =>
      throw const FileSystemException('写入失败');

  @override
  Future<List<String>> list() async => const <String>[];

  @override
  Future<List<SessionEvent>> load(String id) async => const <SessionEvent>[];

  @override
  Future<void> remove(String id) async {}
}

void main() {
  group('提醒服务', () {
    test('创建按顺序编号，列表保持创建顺序', () async {
      final Session session = Session(id: 's1');
      addTearDown(session.close);
      final SessionSchedule schedule = fixedClock(session);
      final ScheduleView first =
          await schedule.create(prompt: '跟进迁移', afterSeconds: 60);
      final ScheduleView second =
          await schedule.create(prompt: '检查构建', afterSeconds: 120);
      expect(first.record.id, 'schedule-1');
      expect(second.record.id, 'schedule-2');
      expect(first.state, ScheduleState.scheduled);
      expect(first.record.scheduledAt, base.add(const Duration(minutes: 1)));
      expect((await schedule.list()).map((ScheduleView v) => v.record.id),
          <String>['schedule-1', 'schedule-2']);
    });

    test('删除未知标识不改变任何状态', () async {
      final Session session = Session(id: 's1');
      addTearDown(session.close);
      final ScheduleDeleteResult result =
          await fixedClock(session).delete('schedule-9');
      expect(result.deleted, isFalse);
      expect(result.toJson()['code'], 'schedule_not_found');
      expect(session.length, 0);
    });

    test('删除活动提醒后列表不再包含它', () async {
      final Session session = Session(id: 's1');
      addTearDown(session.close);
      final SessionSchedule schedule = fixedClock(session);
      final ScheduleView created =
          await schedule.create(prompt: '跟进迁移', afterSeconds: 60);
      final ScheduleDeleteResult result =
          await schedule.delete(created.record.id);
      expect(result.deleted, isTrue);
      expect(await schedule.list(), isEmpty);
    });

    test('输入非法时不写入任何事件', () async {
      final Session session = Session(id: 's1');
      addTearDown(session.close);
      final SessionSchedule schedule = fixedClock(session);
      expect(() => schedule.create(prompt: '  ', afterSeconds: 60),
          throwsA(isA<ScheduleInputException>()));
      expect(() => schedule.create(prompt: 'a', everySeconds: 299),
          throwsA(isA<ScheduleInputException>()));
      expect(session.length, 0);
    });

    test('已到期提醒在列表里标记为 overdue', () async {
      final Session session = Session(id: 's1');
      addTearDown(session.close);
      final SessionSchedule past = SessionSchedule(
          session: session,
          clock: () => base.subtract(const Duration(hours: 1)));
      await past.create(prompt: '跟进迁移', afterSeconds: 60);
      final SessionSchedule now = fixedClock(session);
      expect((await now.list()).single.state, ScheduleState.overdue);
    });
  });

  group('持久化与会话恢复', () {
    test('重启后活动提醒自动重建，已派发的记录不再出现', () async {
      final Directory dir =
          Directory.systemTemp.createTempSync('conatus-schedule');
      addTearDown(() => dir.deleteSync(recursive: true));
      final JsonlSessionPersistence persistence =
          JsonlSessionPersistence(dir: dir.path);

      final SessionStore store = SessionStore(persistence: persistence);
      final Session first = await store.open('s1');
      final SessionSchedule schedule = fixedClock(first, sessions: store);
      final ScheduleView oneShot =
          await schedule.create(prompt: '跟进迁移', afterSeconds: 600);
      final ScheduleView recurring =
          await schedule.create(prompt: '每小时检查', everySeconds: 3600);
      await store.flush();
      schedule.recordDispatch(oneShot.record.id);
      await store.flush();
      first.close();

      final SessionStore reopened = SessionStore(persistence: persistence);
      final Session second = await reopened.open('s1');
      addTearDown(second.close);
      final List<ScheduleView> views =
          await fixedClock(second, sessions: reopened).list();
      expect(views.map((ScheduleView v) => v.record.id),
          <String>[recurring.record.id]);
      expect(views.single.record.prompt, '每小时检查');
      expect(views.single.record.everySeconds, 3600);
    });

    test('持久化写入失败时报告不确定而不是成功', () async {
      final SessionStore store =
          SessionStore(persistence: FailingPersistence());
      final Session session = await store.open('s1');
      addTearDown(session.close);
      final SessionSchedule schedule = fixedClock(session, sessions: store);
      await expectLater(
        schedule.create(prompt: '跟进迁移', afterSeconds: 60),
        throwsA(isA<SchedulePersistenceException>().having(
            (SchedulePersistenceException error) => error.code,
            'code',
            ScheduleErrorCode.persistenceUncertain)),
      );
    });
  });
}
