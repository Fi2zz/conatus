/// 脚本化 LLM：按预设响应序列应答，记录每次请求，供集成测试断言。
library;

import 'dart:convert';
import 'package:conatus_llm/conatus_llm.dart';

/// 按顺序返回预设响应的 [LlmProvider]。脚本耗尽时抛错以暴露漏写的场景。
class ScriptedLlm implements LlmProvider {
  ScriptedLlm(this._script);

  final List<LlmResult> _script;

  /// 记录实际收到的每次请求消息，供断言。
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
    requests.add(List<LlmMessage>.of(messages));
    if (_index >= _script.length) {
      throw StateError('脚本耗尽，收到第 ${_index + 1} 次请求（共 ${_script.length} 条）');
    }
    return _script[_index++];
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

/// 纯文本回复。
LlmResult text(String content) =>
    LlmResult(content: content, provider: 'scripted', model: 'm');

/// 单工具调用回复。
LlmResult callTool(
  String id,
  String name, [
  Map<String, Object?> args = const <String, Object?>{},
]) =>
    LlmResult(
      content: '',
      provider: 'scripted',
      model: 'm',
      toolCalls: <LlmToolCall>[
        LlmToolCall(id: id, name: name, arguments: jsonEncode(args)),
      ],
    );
