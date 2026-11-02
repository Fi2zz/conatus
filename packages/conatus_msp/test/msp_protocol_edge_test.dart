import 'package:conatus_msp/src/msp_pending_calls.dart';
import 'package:conatus_msp/src/msp_signal.dart';
import 'package:conatus_msp/src/msp_tool_result.dart';
import 'package:test/test.dart';

void main() {
  test('可选信封字段类型错误统一为 FormatException', () {
    for (final String key in <String>['pattern', 'target', 'path', 'reqid']) {
      expect(
        () => MspSignal.fromJson(<String, Object?>{
          'type': 'signal',
          'source': 'node_a',
          key: 42,
        }),
        throwsFormatException,
        reason: key,
      );
    }
  });

  test('工具结果错误字段必须具有线上字符串类型', () {
    expect(
      () => MspToolResult.fromPayload(<String, Object?>{'error': 42}),
      throwsFormatException,
    );
  });

  test('畸形响应不会提前删除 pending 请求', () async {
    final MspPendingCalls pending = MspPendingCalls();
    final MspPendingRequest request = pending.create('peer');
    final MspSignalOptions options = MspSignalOptions(reqid: request.id)
      ..payload = <String, Object?>{'error': 42};
    final MspSignal malformed = MspSignal(
      type: 'tool_result',
      source: 'peer',
      options: options,
    );
    expect(() => pending.complete(malformed), throwsFormatException);

    final MspSignal valid = MspSignal(
      type: 'tool_result',
      source: 'peer',
      options: MspSignalOptions(reqid: request.id)
        ..payload = <String, Object?>{
          'content': <Object?>[],
          'structuredContent': 'ok'
        },
    );
    pending.complete(valid);
    expect((await request.completer.future).structured, 'ok');
  });
}
