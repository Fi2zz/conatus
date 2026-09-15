/// layered-compaction 插件：按内容类别分层折叠会话，而不是一律压成一段摘要。
///
/// 服务键 `'compaction'`，与 [provideCompaction] 二选一（同名服务重复提供会抛错）。
/// 与 [Compactor] 的接口与契约完全一致（`compact` / `summaryOf` / `forget` /
/// `keepRecent`），可直接替换进 Agent Loop。区别在 `compact` 的处理方式：
///
/// * 工具结果压成「工具名 + 结果首行 + 字符数」的一行说明，正文丢弃，并指向
///   会话日志里的 `tool/result` 事件（**不**额外落盘）；
/// * 用户偏好原文保留，一字不改；
/// * 早期对话段落交给注入的汇总器产出自然语言摘要；
/// * 近期窗口不处理，留给 Agent Loop 的滑动窗口。
///
/// 产出的摘要是一段分层文本（`[历史摘要]` / `[用户偏好]` / `[工具结果]` /
/// `[保留原文]`），`buildSystemText` 会把它整段塞进 system 的 `[历史摘要]` 块。
library;

import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'agent_events.dart';
import 'agent_types.dart';
import 'compaction.dart';
import 'content_classifier.dart';
import 'context_metrics.dart';
import 'telemetry.dart';

/// 分层压缩器：[Compactor] 的 drop-in 替身，按内容类别分别处理较早事件。
class LayeredCompactor extends Compactor {
  /// [classifier] 缺省为 [RuleBasedContentClassifier]；[telemetry] 为空则不埋点。
  LayeredCompactor({
    super.keepRecent,
    ContentClassifier? classifier,
    Telemetry? telemetry,
  })  : classifier = classifier ?? RuleBasedContentClassifier(),
        _telemetry = telemetry;

  /// 内容分类器：决定每类内容的压缩策略。
  final ContentClassifier classifier;

  final Telemetry? _telemetry;
  final Map<String, String> _summaries = <String, String>{};

  @override
  String? summaryOf(String sessionId) => _summaries[sessionId];

  @override
  void forget(String sessionId) => _summaries.remove(sessionId);

  @override
  Future<CompactionResult?> compact(
    Session session,
    Summarizer summarize, {
    int? keepRecent,
  }) async {
    final int keep = keepRecent ?? this.keepRecent;
    final List<SessionEvent> events = session.events;
    if (events.length <= keep) return null;
    final int olderEnd = events.length - keep;
    final _Layers layers = _collect(events, olderEnd);
    final String summary =
        await summarize(layers.conversation, _summaries[session.id] ?? '');
    final String text = _render(summary.trim(), layers);
    _summaries[session.id] = text;
    _telemetry
        ?.emit(TelemetryEvent('context.compacted', data: <String, Object?>{
      'tokensBefore': estimateMessagesTokens(
          deriveAgentMessages(_messageEvents(events, olderEnd))),
      'tokensAfter': estimateTokens(text),
      'compacted': olderEnd,
      'kept': keep,
      'toolResults': layers.toolNotes.length,
      'preferences': layers.preferences.length,
    }));
    return CompactionResult(summary: text, compacted: olderEnd, kept: keep);
  }

  _Layers _collect(List<SessionEvent> events, int olderEnd) {
    final List<SessionEvent> older = _messageEvents(events, olderEnd);
    final List<LlmMessage> messages = deriveAgentMessages(older);
    final _Layers layers = _Layers();
    for (int index = 0; index < older.length; index++) {
      final LlmMessage message = messages[index];
      final MessageCategory category =
          _categoryOf(message, older.length - index);
      layers.add(
          older[index], message, category, classifier.strategyFor(category));
    }
    return layers;
  }

  /// 只保留「会被 `deriveAgentMessages` 还原成一条消息」的事件，保证事件与
  /// 消息按下标一一对应。
  List<SessionEvent> _messageEvents(List<SessionEvent> events, int olderEnd) =>
      <SessionEvent>[
        for (int index = 0; index < olderEnd; index++)
          if (_carriesMessage(events[index])) events[index],
      ];

  bool _carriesMessage(SessionEvent event) {
    if (event.data is! Map) return false;
    if (event.type == kUserMessageEvent) return true;
    if (event.type == kAssistantMessageEvent) return true;
    return event.type == kToolResultEvent;
  }

  MessageCategory _categoryOf(LlmMessage message, int indexFromEnd) {
    final MessageCategory base = classifier.classify(message);
    if (base != MessageCategory.recentConversation) return base;
    return indexFromEnd > classifier.recentWindow
        ? MessageCategory.earlyConversation
        : base;
  }

  String _render(String summary, _Layers layers) {
    final StringBuffer buffer = StringBuffer();
    _writeSection(buffer, '历史摘要', <String>[
      if (summary.isNotEmpty) summary,
    ]);
    _writeSection(buffer, '用户偏好', layers.preferences);
    _writeSection(buffer, '工具结果', layers.toolNotes);
    _writeSection(buffer, '保留原文', layers.retained);
    return buffer.toString().trim();
  }

  void _writeSection(StringBuffer buffer, String title, List<String> lines) {
    if (lines.isEmpty) return;
    buffer.writeln('[$title]');
    for (final String line in lines) {
      buffer.writeln('- ${line.trim()}');
    }
    buffer.writeln();
  }
}

/// 分层结果的分桶：按策略把较早事件归入偏好 / 工具结果 / 摘要 / 保留原文。
class _Layers {
  final List<String> preferences = <String>[];
  final List<String> toolNotes = <String>[];
  final List<String> retained = <String>[];
  final List<SessionEvent> conversation = <SessionEvent>[];

  void add(SessionEvent event, LlmMessage message, MessageCategory category,
      CompressionStrategy strategy) {
    if (strategy == CompressionStrategy.evict) {
      toolNotes.add(_toolNote(event, message.content));
      return;
    }
    if (category == MessageCategory.userPreference) {
      preferences.add(message.content);
      return;
    }
    if (strategy == CompressionStrategy.summarize) {
      conversation.add(event);
      return;
    }
    retained.add(message.content);
  }

  String _toolNote(SessionEvent event, String content) {
    final Object? data = event.data;
    final String name = data is Map ? '${data['name'] ?? 'tool'}' : 'tool';
    return '工具 $name：${_headline(content)}'
        '（原结果 ${content.length} 字符，完整内容见会话日志中的 $kToolResultEvent 事件）';
  }

  String _headline(String content) {
    final String first = content.split('\n').first.trim();
    return first.length <= 80 ? first : '${first.substring(0, 80)}…';
  }
}

/// 把 [LayeredCompactor] 作为 `'compaction'` 服务提供到上下文。
///
/// 与 [provideCompaction]（朴素压缩器）二选一：两者都注册 `'compaction'`，
/// 同一上下文里重复提供会抛错。[classifier] / [telemetry] 缺省取上下文里
/// 已提供的 `'contentClassifier'` / `'telemetry'`。
LayeredCompactor provideLayeredCompaction(
  Context ctx, {
  Compactor? compaction,
  ContentClassifier? classifier,
  Telemetry? telemetry,
  int? keepRecent,
}) {
  final LayeredCompactor resolved = compaction is LayeredCompactor
      ? compaction
      : LayeredCompactor(
          keepRecent: keepRecent ?? compaction?.keepRecent ?? 20,
          classifier:
              classifier ?? ctx.get<ContentClassifier>('contentClassifier'),
          telemetry: telemetry ?? ctx.get<Telemetry>('telemetry'),
        );
  ctx.provide('compaction', resolved);
  return resolved;
}
