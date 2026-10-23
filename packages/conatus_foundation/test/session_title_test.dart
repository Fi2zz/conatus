import 'dart:io';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

void main() {
  group('Session.title / rename', () {
    test('rename 追加标题事件，getter 取最后一个', () {
      final Session session = Session(id: 's1');
      expect(session.title, isNull);

      session.rename('Auth cleanup');
      expect(session.title, 'Auth cleanup');

      session.rename('Second title');
      expect(session.title, 'Second title');
      expect(
        session.events.where((SessionEvent e) => e.type == kSessionTitleEvent),
        hasLength(2),
      );
      expect(
        session.events
            .firstWhere((SessionEvent e) => e.type == kSessionTitleEvent)
            .data,
        <String, Object?>{'title': 'Auth cleanup'},
      );
    });

    test('rename 修剪空白，空标题抛 ArgumentError', () {
      final Session session = Session(id: 's1');

      expect(() => session.rename(''), throwsArgumentError);
      expect(() => session.rename('   '), throwsArgumentError);
      expect(session.title, isNull);
      expect(session.length, 0);

      session.rename('  Auth cleanup  ');
      expect(session.title, 'Auth cleanup');
    });

    test('过长标题截断到 80 字符', () {
      final Session session = Session(id: 's1');
      session.rename('x' * 100);

      expect(session.title, hasLength(80));
      expect(session.title, 'x' * 80);
    });

    test('旧会话无标题事件时返回 null 且不写回', () {
      final Session session = Session(
        id: 'legacy',
        seed: <SessionEvent>[
          SessionEvent(seq: 0, type: kUserMessageEvent, time: DateTime(2020)),
          SessionEvent(
            seq: 1,
            type: kAssistantMessageEvent,
            time: DateTime(2020),
          ),
        ],
      );

      expect(session.title, isNull);
      expect(session.length, 2);
      expect(session.events, hasLength(2));
    });
  });

  group('fork 与持久化', () {
    test('fork 继承标题前缀，之后可独立改名', () {
      final Session source = Session(id: 'source');
      source.append(kUserMessageEvent, data: <String, Object?>{'text': 'hi'});
      source.rename('Source title');

      final Session fork = source.fork(id: 'fork');

      expect(fork.title, 'Source title');
      expect(fork.ownEvents, isEmpty);
      fork.rename('Fork title');
      expect(fork.title, 'Fork title');
      expect(source.title, 'Source title');
    });

    test('标题事件经 SessionStore JSONL 往返保留', () async {
      final Directory dir =
          Directory.systemTemp.createTempSync('conatus-title-test-');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      final JsonlSessionPersistence persistence =
          JsonlSessionPersistence(dir: dir.path);
      final SessionStore store = SessionStore(persistence: persistence);
      final Session session = store.create(id: 's1');
      session.append(kUserMessageEvent, data: <String, Object?>{'text': '你好'});
      session.rename('持久化标题');
      await store.flush();

      final SessionStore reopened = SessionStore(persistence: persistence);
      final Session loaded = await reopened.open('s1');

      expect(loaded.title, '持久化标题');
      expect(loaded.events.map((SessionEvent e) => e.type), <String>[
        kUserMessageEvent,
        kSessionTitleEvent,
      ]);
    });
  });
}
