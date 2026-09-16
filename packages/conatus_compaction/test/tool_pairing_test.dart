import 'package:conatus_compaction/conatus_compaction.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

Session _plain(int events) {
  final Session session = Session(id: 's1');
  for (int i = 0; i < events; i++) {
    session.append('e$i');
  }
  return session;
}

/// 用户 → 助手发起一次工具调用 → 工具结果。
Session _toolPair() {
  final Session session = Session(id: 's1');
  session.append(kUserMessageEvent, data: <String, Object?>{'text': '查一下'});
  session.append(kAssistantMessageEvent, data: <String, Object?>{
    'text': '',
    'toolCalls': <Map<String, Object?>>[
      <String, Object?>{'id': 'c1', 'name': 'search', 'arguments': '{}'},
    ],
  });
  session.append(kToolResultEvent,
      data: <String, Object?>{'callId': 'c1', 'content': '结果'});
  return session;
}

void main() {
  group('toolPairingBalancedBefore / After', () {
    test('没有工具调用的日志，每个切点都平衡', () {
      final Session session = _plain(3);

      expect(toolPairingBalancedBefore(session, 0), isTrue);
      expect(toolPairingBalancedAfter(session, 2), isTrue);
    });

    test('未闭合工具调用两侧的切点不平衡', () {
      final Session session = _toolPair();

      expect(toolPairingBalancedBefore(session, 1), isTrue);
      expect(toolPairingBalancedBefore(session, 2), isFalse);
      expect(toolPairingBalancedAfter(session, 1), isFalse);
      expect(toolPairingBalancedAfter(session, 2), isTrue);
    });

    test('查询后新增的事件照样计入', () {
      final Session session = _toolPair();
      expect(toolPairingBalancedAfter(session, 2), isTrue);

      session.append(kUserMessageEvent, data: <String, Object?>{'text': '再问'});

      expect(toolPairingBalancedAfter(session, 2), isTrue);
      expect(toolPairingBalancedAfter(session, 3), isTrue);
    });

    test('seq 不在日志里时抛错', () {
      final Session session = _plain(2);

      expect(() => toolPairingBalancedBefore(session, 9), throwsStateError);
    });

    test('结果先于调用时抛错', () {
      final Session session = Session(id: 's1')
        ..append(kToolResultEvent,
            data: <String, Object?>{'callId': 'c1', 'content': '结果'});

      expect(() => toolPairingBalancedBefore(session, 0), throwsStateError);
    });
  });

  group('balancedCutAtOrBefore', () {
    test('平衡切点原样返回', () {
      final Session session = _plain(5);

      expect(balancedCutAtOrBefore(session, 3), 3);
    });

    test('不平衡切点向前吸附到最近的平衡位置', () {
      final Session session = _toolPair();

      expect(balancedCutAtOrBefore(session, 2), 1);
      expect(balancedCutAtOrBefore(session, 3), 3);
    });

    test('没有平衡切点时返回 0', () {
      final Session session = Session(id: 's1')
        ..append(kAssistantMessageEvent, data: <String, Object?>{
          'text': '',
          'toolCalls': <Map<String, Object?>>[
            <String, Object?>{'id': 'c1', 'name': 'search', 'arguments': '{}'},
          ],
        });

      expect(balancedCutAtOrBefore(session, 1), 0);
      expect(balancedCutAtOrBefore(session, 0), 0);
    });
  });
}
