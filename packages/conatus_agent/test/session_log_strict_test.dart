import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:test/test.dart';

class _EchoProvider implements LlmProvider {
  int calls = 0;

  @override
  String get name => 'echo';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async {
    calls++;
    return const LlmResult(content: 'ok', provider: 'echo', model: 'm');
  }

  @override
  Stream<LlmStreamEvent> chatStream(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) =>
      const Stream<LlmStreamEvent>.empty();

  @override
  void close() {}
}

/// 装一个「会话里已有『几点』」的记录器。
SessionLogRecorder _attach(bool strict) {
  final SessionLogRecorder recorder =
      SessionLogRecorder(log: InMemorySessionLog(), strictModelVisible: strict);
  final Session session = Session(id: 's1')
    ..append(kUserMessageEvent, data: <String, Object?>{'text': '几点'});
  recorder.attach(session);
  return recorder;
}

void main() {
  group('SessionLogLlmProvider — strictModelVisible 开发模式断言', () {
    test('请求与日志一致：正常发送到底层 provider', () async {
      final _EchoProvider inner = _EchoProvider();
      final SessionLogLlmProvider provider =
          SessionLogLlmProvider(inner, recorder: _attach(true));

      final LlmResult result =
          await provider.chat(<LlmMessage>[const LlmMessage('user', '几点')]);

      expect(result.content, 'ok');
      expect(inner.calls, 1);
    });

    test('请求与日志不一致：发送前抛 StateError，且不调用底层 provider', () async {
      final _EchoProvider inner = _EchoProvider();
      final SessionLogLlmProvider provider =
          SessionLogLlmProvider(inner, recorder: _attach(true));

      await expectLater(
        provider.chat(
          <LlmMessage>[const LlmMessage('user', '日志里没有这句')],
        ),
        throwsStateError,
      );
      expect(inner.calls, 0);
    });

    test('关闭（默认）时不校验：不一致也照常发送', () async {
      final _EchoProvider inner = _EchoProvider();
      final SessionLogLlmProvider provider =
          SessionLogLlmProvider(inner, recorder: _attach(false));

      final LlmResult result = await provider
          .chat(<LlmMessage>[const LlmMessage('user', '日志里没有这句')]);

      expect(result.content, 'ok');
      expect(inner.calls, 1);
    });
  });
}
