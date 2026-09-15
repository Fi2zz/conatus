/// Server-Sent Events（SSE）解析：`text/event-stream` → [SseEvent] 流。
///
/// 这是纯函数式的线协议解析，不依赖 conatus 也不依赖 MCP：按 SSE 规范累积
/// `event:` / `data:` / `id:` 字段，遇空行派发；`:` 开头的注释行忽略；多行
/// `data:` 用换行拼接。EOF 时若还有未派发的 `data:` 也派发一次。
library;

import 'dart:async';
import 'dart:convert';

/// 一条 SSE 事件。
class SseEvent {
  /// 直接构造。
  const SseEvent({this.event, this.data = '', this.id});

  /// `event:` 字段；缺省时由上层按 `message` 语义处理。
  final String? event;

  /// `data:` 字段（多行以 `\n` 拼接）。
  final String data;

  /// `id:` 字段。
  final String? id;

  @override
  String toString() => 'SseEvent(${event ?? 'message'}: ${data.length} 字节)';
}

/// 把字节流解析为 SSE 事件流。
///
/// 用显式的订阅 + 控制器而非 `async*`：`async*` 生成的流在源流还没结束时
/// **取消永远不完成**（生成器停在 `await for` 里），那会让
/// `SseTransport.disconnect` 挂死。这里的 `onCancel` 把取消传导给源订阅。
Stream<SseEvent> parseSseEvents(Stream<List<int>> bytes) {
  final StreamController<SseEvent> events = StreamController<SseEvent>();
  final _SseBuffer buffer = _SseBuffer();
  final StreamSubscription<String> lines =
      bytes.transform(utf8.decoder).transform(const LineSplitter()).listen(
    (String line) => _dispatchInto(buffer.consume(line), events),
    onError: events.addError,
    onDone: () {
      _dispatchInto(buffer.consume(''), events);
      events.close();
    },
  );
  events.onCancel = lines.cancel;
  return events.stream;
}

void _dispatchInto(SseEvent? event, StreamController<SseEvent> events) {
  if (event != null) events.add(event);
}

/// 跨 chunk 累积字段的状态机。
class _SseBuffer {
  final StringBuffer _data = StringBuffer();
  String? _event;
  String? _id;

  /// 吃一行，返回该行派发出的完整事件（没有则 `null`）。
  SseEvent? consume(String line) {
    if (line.isEmpty) return _dispatch();
    if (line.startsWith(':')) return null;
    final int colon = line.indexOf(':');
    _apply(colon < 0 ? line : line.substring(0, colon), _valueOf(line, colon));
    return null;
  }

  void _apply(String field, String value) {
    if (field == 'event') {
      _event = value;
      return;
    }
    if (field == 'data') {
      _append(value);
      return;
    }
    if (field == 'id') {
      _id = value;
    }
  }

  void _append(String value) {
    if (_data.isNotEmpty) _data.write('\n');
    _data.write(value);
  }

  SseEvent? _dispatch() {
    final SseEvent event = SseEvent(
      event: _event,
      data: _data.toString(),
      id: _id,
    );
    _event = null;
    _id = null;
    _data.clear();
    return event.data.isEmpty ? null : event;
  }
}

String _valueOf(String line, int colon) {
  if (colon < 0) return '';
  final String raw = line.substring(colon + 1);
  return raw.startsWith(' ') ? raw.substring(1) : raw;
}
