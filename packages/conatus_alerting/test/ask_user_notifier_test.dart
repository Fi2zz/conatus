import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_alerting/conatus_alerting.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_tts/conatus_tts.dart';
import 'package:test/test.dart';

import 'support/recording_notifier.dart';

void main() {
  group('AskUserNotifier', () {
    Alert sample() => Alert(
          id: 'a1',
          rule: 'llm-slow',
          severity: AlertSeverity.warning,
          event: TelemetryEvent('llm.request'),
          firedAt: DateTime(2026),
        );

    test('无 TTS 时降级为文本提问', () async {
      final MockAskUser askUser = MockAskUser('y');
      final AskUserNotifier notifier = AskUserNotifier(askUser: askUser);

      await notifier.notify(sample());

      expect(askUser.prompts, hasLength(1));
      expect(askUser.prompts.single, contains('有点慢'));
    });

    test('口语化规则转成播报句子', () async {
      final MockAskUser askUser = MockAskUser('y');
      final AskUserNotifier notifier = AskUserNotifier(askUser: askUser);
      for (final String rule in <String>[
        'llm-slow',
        'tool-failures',
        'session-budget',
        'agent-loop',
        'subagent-stuck',
      ]) {
        await notifier.notify(Alert(
          id: rule,
          rule: rule,
          severity: AlertSeverity.warning,
          event: TelemetryEvent('e'),
          firedAt: DateTime(2026),
        ));
      }
      expect(askUser.prompts, hasLength(5));
      expect(askUser.prompts[1], contains('换个方法'));
    });

    test('肯定回答触发 onUserAccepted', () async {
      final MockAskUser askUser = MockAskUser('换一个');
      final List<Alert> accepted = <Alert>[];
      final List<Alert> rejected = <Alert>[];
      final AskUserNotifier notifier = AskUserNotifier(
        askUser: askUser,
        onUserAccepted: accepted.add,
        onUserRejected: rejected.add,
      );

      await notifier.notify(sample());

      expect(accepted, hasLength(1));
      expect(rejected, isEmpty);
    });

    test('否定回答触发 onUserRejected', () async {
      final MockAskUser askUser = MockAskUser('不要');
      final List<Alert> accepted = <Alert>[];
      final List<Alert> rejected = <Alert>[];
      final AskUserNotifier notifier = AskUserNotifier(
        askUser: askUser,
        onUserAccepted: accepted.add,
        onUserRejected: rejected.add,
      );

      await notifier.notify(sample());

      expect(rejected, hasLength(1));
      expect(accepted, isEmpty);
    });

    test('TTS 与 sink 齐备时播报而非提问', () async {
      final MockAskUser askUser = MockAskUser('y');
      final TtsService tts = TtsService();
      tts.register(_FakeTtsProvider());
      final BytesAudioSink sink = BytesAudioSink();
      final AskUserNotifier notifier =
          AskUserNotifier(askUser: askUser, tts: tts, sink: sink);

      await notifier.notify(sample());

      expect(askUser.prompts, isEmpty, reason: '已走 TTS 播报');
      expect(sink.bytes, isNotEmpty);
    });

    test('提问失败只记录不抛异常', () async {
      final AskUserNotifier notifier =
          AskUserNotifier(askUser: _ThrowingAskUser());
      await notifier.notify(sample()); // 不抛
    });
  });
}

class _FakeTtsProvider implements TtsProvider {
  @override
  String get name => 'fake';

  @override
  TtsAudioFormat get audioFormat => const TtsAudioFormat();

  @override
  TtsVoice? get defaultVoice => null;

  @override
  Future<TtsSession> start(
    TtsAudioSink sink, {
    TtsVoice? voice,
    TtsAudioFormat? format,
    double? speed,
    double? volume,
    double? pitch,
  }) async {
    sink.write(<int>[1, 2, 3]);
    await sink.close();
    return _FakeSession();
  }
}

class _FakeSession implements TtsSession {
  @override
  void send(String text) {}

  @override
  Future<void> finish() async {}

  @override
  void close() {}
}

class _ThrowingAskUser implements AskUser {
  @override
  Future<String> ask(String prompt) async => throw StateError('ask failed');

  @override
  void cancel() {}
}
