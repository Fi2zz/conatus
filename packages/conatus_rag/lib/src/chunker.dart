import 'dart:convert';
import 'dart:math' as math;

import 'package:conatus_foundation/conatus_foundation.dart';

import 'rag_chunk.dart';
import 'rag_scope.dart';

const String _truncationMark = '…[截断]';

/// 把会话事件切成带来源的原文块。事件按白名单转文本，窗口按字符滑动。
List<RagChunk> chunkEvents(
  RagSource source,
  Iterable<SessionEvent> events,
  ChunkerConfig config,
) {
  final int step = config.chunkChars - config.overlapChars;
  if (step <= 0) {
    throw ArgumentError.value(config, 'config', 'overlapChars 必须小于 chunkChars');
  }
  final List<_Line> lines = _layout(events, config.maxChunkChars);
  final String buffer = lines.map((_Line l) => l.text).join('\n');
  final List<RagChunk> chunks = <RagChunk>[];
  for (int start = 0; start < buffer.length; start += step) {
    final int end = math.min(start + config.chunkChars, buffer.length);
    final List<_Line> hit = lines
        .where((_Line l) => l.start < end && l.end > start)
        .toList(growable: false);
    if (hit.isNotEmpty) {
      chunks.add(_buildChunk(source, buffer.substring(start, end), hit));
    }
    if (end == buffer.length) break;
  }
  return chunks;
}

/// 事件的可索引文本；未知或被过滤的事件返回空串。
String eventText(SessionEvent event) {
  final Map<String, Object?> data = _dataOf(event);
  return switch (event.type) {
    kUserMessageEvent => '用户：${data['text'] ?? ''}',
    kAssistantMessageEvent => '助手：${data['text'] ?? ''}',
    'tool/call' => '工具调用 ${data['name']}(${jsonEncode(data['args'])})',
    kToolResultEvent => '工具结果 ${data['name']}：${data['content'] ?? ''}',
    _ => '',
  };
}

Map<String, Object?> _dataOf(SessionEvent event) {
  final Object? data = event.data;
  return data is Map ? data.cast<String, Object?>() : const <String, Object?>{};
}

List<_Line> _layout(Iterable<SessionEvent> events, int maxChars) {
  final List<_Line> lines = <_Line>[];
  int offset = 0;
  for (final SessionEvent event in events) {
    final String text = _clip(eventText(event), maxChars);
    if (text.isEmpty) continue;
    lines.add(_Line(event, text, offset, offset + text.length));
    offset += text.length + 1;
  }
  return lines;
}

String _clip(String text, int maxChars) => text.length <= maxChars
    ? text
    : '${text.substring(0, maxChars)}$_truncationMark';

RagChunk _buildChunk(RagSource source, String text, List<_Line> hit) {
  final List<DateTime> times =
      hit.map((_Line l) => l.event.time).toList(growable: false);
  final int firstSeq = hit.first.event.seq;
  final int lastSeq = hit.last.event.seq;
  return RagChunk(
    id: '${source.sourceKind}/${source.sourceId}/$firstSeq-$lastSeq',
    tenantId: source.scope.tenantId,
    sourceKind: source.sourceKind,
    sourceId: source.sourceId,
    visibilityTags: source.scope.visibilityTags,
    firstSeq: firstSeq,
    lastSeq: lastSeq,
    eventIds: hit.map((_Line l) => l.event.id).whereType<String>().toSet(),
    startTime: times.reduce((DateTime a, DateTime b) => a.isBefore(b) ? a : b),
    endTime: times.reduce((DateTime a, DateTime b) => a.isAfter(b) ? a : b),
    text: text,
  );
}

class _Line {
  const _Line(this.event, this.text, this.start, this.end);

  final SessionEvent event;
  final String text;
  final int start;
  final int end;
}
