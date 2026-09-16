import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_schedule/conatus_schedule.dart';
import 'package:test/test.dart';

SessionEvent changeEvent(int seq, Object? data) => SessionEvent.create(
      sessionId: 's1',
      type: kScheduleChangeEvent,
      seq: seq,
      data: data,
    );

Map<String, Object?> atRecord({
  String id = 'schedule-1',
  String prompt = '提醒',
  String scheduledAt = '2026-08-06T00:00:00.000Z',
}) =>
    <String, Object?>{
      'id': id,
      'kind': 'at',
      'prompt': prompt,
      'scheduledAt': scheduledAt,
    };

Map<String, Object?> createPayload(Map<String, Object?> record) =>
    <String, Object?>{'version': 1, 'operation': 'create', 'schedule': record};

void main() {
  group('严格解码：变更载荷', () {
    test('解码三种创建记录并保留字段', () {
      final ScheduleChange after =
          decodeScheduleChange(createPayload(<String, Object?>{
        'id': 'schedule-1',
        'kind': 'after',
        'prompt': '跟进迁移',
        'afterSeconds': 600,
        'scheduledAt': '2026-08-06T00:10:00.000Z',
      }));
      final ScheduleRecord afterRecord = (after as ScheduleCreateChange).record;
      expect(afterRecord.kind, ScheduleKind.after);
      expect(afterRecord.afterSeconds, 600);
      expect(afterRecord.scheduledAt, DateTime.utc(2026, 8, 6, 0, 10));

      final ScheduleChange every =
          decodeScheduleChange(createPayload(<String, Object?>{
        'id': 'schedule-2',
        'kind': 'every',
        'prompt': '检查构建',
        'everySeconds': 300,
        'scheduledAt': '2026-08-06T00:05:00.000Z',
      }));
      expect((every as ScheduleCreateChange).record.everySeconds, 300);
    });

    test('解码删除与两种派发形状', () {
      final ScheduleChange delete = decodeScheduleChange(<String, Object?>{
        'version': 1,
        'operation': 'delete',
        'id': 'schedule-1'
      });
      expect((delete as ScheduleDeleteChange).id, 'schedule-1');

      final ScheduleChange oneShot = decodeScheduleChange(<String, Object?>{
        'version': 1,
        'operation': 'dispatch',
        'id': 'schedule-1'
      });
      expect((oneShot as ScheduleDispatchChange).acceptedAt, isNull);

      final ScheduleChange every = decodeScheduleChange(<String, Object?>{
        'version': 1,
        'operation': 'dispatch',
        'id': 'schedule-2',
        'acceptedAt': '2026-08-06T00:20:00.000Z',
      });
      expect((every as ScheduleDispatchChange).acceptedAt,
          DateTime.utc(2026, 8, 6, 0, 20));
    });

    test('拒绝版本、形状与字段集合违规', () {
      final List<Object?> bad = <Object?>[
        'not-an-object',
        <String, Object?>{'version': 2, 'operation': 'delete', 'id': 'a'},
        <String, Object?>{'version': 1, 'operation': 'purge', 'id': 'a'},
        <String, Object?>{'version': 1, 'operation': 'delete'},
        <String, Object?>{
          'version': 1,
          'operation': 'delete',
          'id': 'a',
          'extra': 1,
        },
        <String, Object?>{'version': 1, 'operation': 'delete', 'id': ''},
        <String, Object?>{'version': 1, 'operation': 'delete', 'id': ' a'},
        <String, Object?>{
          'version': 1,
          'operation': 'dispatch',
          'id': 'a',
          'when': 1
        },
        createPayload(
            <String, Object?>{'id': 'a', 'kind': 'at', 'prompt': 'p'}),
      ];
      for (final Object? payload in bad) {
        expect(() => decodeScheduleChange(payload),
            throwsA(isA<ScheduleLogException>()),
            reason: '应当拒绝 $payload');
      }
    });
  });

  group('严格解码：记录形状', () {
    test('拒绝额外字段、错误 prompt 与非法数值', () {
      final List<Object?> bad = <Object?>[
        <String, Object?>{
          'id': 'a',
          'kind': 'nope',
          'prompt': 'p',
          'scheduledAt': 'x'
        },
        <String, Object?>{
          'id': 'a',
          'kind': 'at',
          'prompt': ' p',
          'scheduledAt': '2026-08-06T00:00:00.000Z'
        },
        <String, Object?>{
          'id': 'a',
          'kind': 'at',
          'prompt': '',
          'scheduledAt': '2026-08-06T00:00:00.000Z'
        },
        <String, Object?>{
          'id': 'a',
          'kind': 'at',
          'prompt': 'p',
          'scheduledAt': '2026-08-06T00:00:00.000Z',
          'everySeconds': 300,
        },
        <String, Object?>{
          'id': 'a',
          'kind': 'after',
          'prompt': 'p',
          'afterSeconds': 0,
          'scheduledAt': '2026-08-06T00:00:00.000Z',
        },
        <String, Object?>{
          'id': 'a',
          'kind': 'after',
          'prompt': 'p',
          'afterSeconds': 1.5,
          'scheduledAt': '2026-08-06T00:00:00.000Z',
        },
        <String, Object?>{
          'id': 'a',
          'kind': 'every',
          'prompt': 'p',
          'everySeconds': 299,
          'scheduledAt': '2026-08-06T00:00:00.000Z',
        },
        <String, Object?>{
          'id': 'a',
          'kind': 'at',
          'prompt': 'p',
          'scheduledAt': '2026-02-30T00:00:00.000Z',
        },
        <String, Object?>{
          'id': 'a',
          'kind': 'at',
          'prompt': 'p',
          'scheduledAt': '2026-08-06T00:00:00+08:00',
        },
      ];
      for (final Object? record in bad) {
        expect(() => decodeScheduleRecord(record),
            throwsA(isA<ScheduleLogException>()),
            reason: '应当拒绝 $record');
      }
    });
  });

  group('折叠', () {
    test('保持创建顺序并累计用过的标识', () {
      final ScheduleFold folded = foldScheduleEvents(<SessionEvent>[
        changeEvent(0, createPayload(atRecord())),
        changeEvent(1, createPayload(atRecord(id: 'schedule-2'))),
        changeEvent(2, <String, Object?>{
          'version': 1,
          'operation': 'delete',
          'id': 'schedule-1',
        }),
      ]);
      expect(folded.active.single.id, 'schedule-2');
      expect(folded.seenIds, <String>['schedule-1', 'schedule-2']);
    });

    test('拒绝 id 复用与指向非活动记录的转换', () {
      expect(
        () => foldScheduleEvents(<SessionEvent>[
          changeEvent(0, createPayload(atRecord())),
          changeEvent(1, createPayload(atRecord())),
        ]),
        throwsA(isA<ScheduleLogException>()),
      );
      expect(
        () => foldScheduleEvents(<SessionEvent>[
          changeEvent(0, <String, Object?>{
            'version': 1,
            'operation': 'delete',
            'id': 'schedule-9',
          }),
        ]),
        throwsA(isA<ScheduleLogException>()),
      );
      expect(
        () => foldScheduleEvents(<SessionEvent>[
          changeEvent(0, <String, Object?>{
            'version': 1,
            'operation': 'dispatch',
            'id': 'schedule-9',
          }),
        ]),
        throwsA(isA<ScheduleLogException>()),
      );
    });

    test('一次性派发终结记录，固定间隔派发推进目标', () {
      final ScheduleFold folded = foldScheduleEvents(<SessionEvent>[
        changeEvent(0, createPayload(atRecord())),
        changeEvent(
            1,
            createPayload(<String, Object?>{
              'id': 'schedule-2',
              'kind': 'every',
              'prompt': '检查',
              'everySeconds': 300,
              'scheduledAt': '2026-08-06T00:00:00.000Z',
            })),
        changeEvent(2, <String, Object?>{
          'version': 1,
          'operation': 'dispatch',
          'id': 'schedule-1',
        }),
      ]);
      expect(folded.active.single.id, 'schedule-2');

      final ScheduleFold advanced = foldScheduleEvents(<SessionEvent>[
        changeEvent(
            0,
            createPayload(<String, Object?>{
              'id': 'schedule-1',
              'kind': 'every',
              'prompt': '检查',
              'everySeconds': 300,
              'scheduledAt': '2026-08-06T00:00:00.000Z',
            })),
        changeEvent(1, <String, Object?>{
          'version': 1,
          'operation': 'dispatch',
          'id': 'schedule-1',
          'acceptedAt': '2026-08-06T00:12:00.000Z',
        }),
      ]);
      expect(
          advanced.active.single.scheduledAt, DateTime.utc(2026, 8, 6, 0, 15));
    });

    test('一次性派发带 acceptedAt、固定间隔派发缺 acceptedAt 均被拒绝', () {
      final Map<String, Object?> oneShot = createPayload(atRecord());
      expect(
        () => foldScheduleEvents(<SessionEvent>[
          changeEvent(0, oneShot),
          changeEvent(1, <String, Object?>{
            'version': 1,
            'operation': 'dispatch',
            'id': 'schedule-1',
            'acceptedAt': '2026-08-06T00:00:00.000Z',
          }),
        ]),
        throwsA(isA<ScheduleLogException>()),
      );
      expect(
        () => foldScheduleEvents(<SessionEvent>[
          changeEvent(
              0,
              createPayload(<String, Object?>{
                'id': 'schedule-1',
                'kind': 'every',
                'prompt': '检查',
                'everySeconds': 300,
                'scheduledAt': '2026-08-06T00:00:00.000Z',
              })),
          changeEvent(1, <String, Object?>{
            'version': 1,
            'operation': 'dispatch',
            'id': 'schedule-1',
          }),
        ]),
        throwsA(isA<ScheduleLogException>()),
      );
    });

    test('固定间隔推进到范围之外时记录终结', () {
      final ScheduleFold folded = foldScheduleEvents(<SessionEvent>[
        changeEvent(
            0,
            createPayload(<String, Object?>{
              'id': 'schedule-1',
              'kind': 'every',
              'prompt': '检查',
              'everySeconds': 300,
              'scheduledAt': '9999-12-31T23:59:59.000Z',
            })),
        changeEvent(1, <String, Object?>{
          'version': 1,
          'operation': 'dispatch',
          'id': 'schedule-1',
          'acceptedAt': '9999-12-31T23:59:59.999Z',
        }),
      ]);
      expect(folded.active, isEmpty);
      expect(folded.seenIds, <String>['schedule-1']);
    });
  });

  group('会话切点与标识分配', () {
    test('fork 出的会话不继承父会话的活动提醒', () {
      final Session parent = Session(id: 'parent');
      parent.append(kScheduleChangeEvent, data: createPayload(atRecord()));
      final Session child = parent.fork(id: 'child');
      expect(child.inheritedEventCount, parent.length);
      expect(foldScheduleEvents(child.ownEvents).active, isEmpty);
      expect(foldScheduleEvents(parent.ownEvents).active.length, 1);
    });

    test('标识分配不复用任何用过的标识', () {
      expect(
        allocateScheduleId(ScheduleFold(
            active: const <ScheduleRecord>[], seenIds: const <String>[])),
        'schedule-1',
      );
      expect(
        allocateScheduleId(ScheduleFold(
          active: const <ScheduleRecord>[],
          seenIds: const <String>['custom', 'schedule-3'],
        )),
        'schedule-4',
      );
      expect(
        allocateScheduleId(ScheduleFold(
          active: const <ScheduleRecord>[],
          seenIds: const <String>['one', 'schedule-2'],
        )),
        'schedule-3',
      );
    });
  });
}
