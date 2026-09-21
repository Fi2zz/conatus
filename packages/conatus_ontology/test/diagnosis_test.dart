import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:conatus_ontology/src/evolver/diagnosis.dart';
import 'package:test/test.dart';

/// 按脚本回复的 LLM，并记录收到的请求。
class _ScriptedProvider implements LlmProvider {
  _ScriptedProvider(this.replies);

  final List<String> replies;
  final List<List<LlmMessage>> requests = <List<LlmMessage>>[];
  int _index = 0;

  @override
  String get name => 'scripted';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async {
    requests.add(messages);
    final String reply = replies[_index.clamp(0, replies.length - 1)];
    _index++;
    return LlmResult(content: reply, provider: name, model: 'test');
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

void main() {
  group('parseDiagnosis', () {
    test('解析错误数组', () {
      final SemanticDiagnosis diagnosis = parseDiagnosis(
        '[{"description": "术语理解错误", "manifestation": "查询失败", '
        '"fixDirection": "补充定义", "traceIds": ["t1", "t2"]}]',
      );
      expect(diagnosis.errors, hasLength(1));
      final SemanticError error = diagnosis.errors.single;
      expect(error.description, '术语理解错误');
      expect(error.manifestation, '查询失败');
      expect(error.fixDirection, '补充定义');
      expect(error.traceIds, <String>['t1', 't2']);
    });

    test('非法 JSON 抛 FormatException', () {
      expect(() => parseDiagnosis('nope'), throwsFormatException);
    });
  });

  group('diagnose', () {
    test('构造 prompt 并解析诊断', () async {
      final _ScriptedProvider llm = _ScriptedProvider(<String>[
        '[{"description": "d", "manifestation": "m", "fixDirection": "f"}]',
      ]);
      final List<SessionEvent> traces = <SessionEvent>[
        SessionEvent.create(
            sessionId: 's1', type: kUserMessageEvent, seq: 0, data: <String, Object?>{'text': '查营收'}),
        SessionEvent.create(
            sessionId: 's1', type: kToolResultEvent, seq: 1, data: <String, Object?>{'text': '错误'}),
      ];
      final SemanticDiagnosis result = await diagnose(llm, traces);
      expect(result.errors, hasLength(1));
      expect(llm.requests, hasLength(1));
      expect(llm.requests.single.first.role, 'system');
      expect(llm.requests.single.last.content, contains('user/message'));
    });
  });
}
