/// Demo 用的离线脚本化模型：按「谁在说话」返回确定性结论，无需 API Key。
///
/// 成员运行时把成员人设放进 `messages[0]`（兜底人设形如
/// `你是团队成员「性能」，完成任务后简短回复结论。`），本模型据此识别
/// 发言者，再按该成员的调用次数给出台词——顺序 / 并发 / 群聊 /
/// Maker-Checker 四种模式于是都能离线跑通且结果可复现。
library;

import 'package:conatus_llm/conatus_llm.dart';

/// 离线脚本化模型。
class TeamDemoModel implements LlmProvider {
  final Map<String, int> _calls = <String, int>{};

  @override
  String get name => 'team-demo';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async {
    final String speaker = _speaker(messages);
    final int nth = (_calls[speaker] ?? 0) + 1;
    _calls[speaker] = nth;
    return LlmResult(
      content: _script(speaker, nth),
      provider: name,
      model: 'demo-1',
    );
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

  /// 从 system 消息里读成员名；读不到时视为队长。
  String _speaker(List<LlmMessage> messages) {
    if (messages.isEmpty) return 'lead';
    final RegExpMatch? match =
        RegExp(r'「(.+?)」').firstMatch(messages.first.content);
    return match?.group(1) ?? 'lead';
  }

  /// 每个成员的确定性台词；未知成员回落到通用结论。
  String _script(String speaker, int nth) {
    switch (speaker) {
      case '性能':
        return '性能结论：峰值下热点在支付校验，建议加本地缓存并压测回归。';
      case '安全':
        return '安全结论：回调未验签，存在伪造风险，需补 HMAC 校验。';
      case '产品':
        return '产品结论：支付路径 5 步偏长，建议合并确认页。';
      case '提案人':
        return nth == 1
            ? '提案 V1：引入 Redis 缓存热点键。'
            : '提案 V2：Redis 缓存 + 空值保护，并补充降级说明。';
      case '审查者':
        return nth == 1 ? '不通过：缺少缓存穿透的降级说明。' : '通过：认可，可以落地。';
      default:
        return '$speaker 已完成。';
    }
  }
}
