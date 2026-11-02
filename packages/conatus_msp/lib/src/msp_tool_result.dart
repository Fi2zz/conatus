import 'dart:convert';

class MspToolResult {
  const MspToolResult({
    this.content = const <Map<String, Object?>>[],
    this.structured,
    this.error = '',
  });

  factory MspToolResult.fromValue(Object? value) {
    if (value == null) return const MspToolResult();
    if (value is String) return _structured(value, value);
    return _structured(value, jsonEncode(value));
  }

  factory MspToolResult.fromPayload(Map<String, Object?> payload) {
    final Object? raw = payload['content'];
    final List<Map<String, Object?>> content = raw is List
        ? raw
            .whereType<Map<String, Object?>>()
            .map(Map<String, Object?>.from)
            .toList()
        : <Map<String, Object?>>[];
    return MspToolResult(
      content: content,
      structured: payload['structuredContent'],
      error: payload['error'] as String? ?? '',
    );
  }

  factory MspToolResult.failure(String message) =>
      MspToolResult(error: message);

  final List<Map<String, Object?>> content;
  final Object? structured;
  final String error;

  bool get failed => error.isNotEmpty;

  String get text => content
      .where((Map<String, Object?> block) => block['type'] == 'text')
      .map((Map<String, Object?> block) => '${block['text'] ?? ''}')
      .join('\n');

  Map<String, Object?> toPayload() => failed
      ? <String, Object?>{'content': <Object?>[], 'error': error}
      : <String, Object?>{
          'content': content,
          'structuredContent': structured,
        };
}

MspToolResult _structured(Object? value, String text) => MspToolResult(
      content: <Map<String, Object?>>[
        <String, Object?>{'type': 'text', 'text': text},
      ],
      structured: value,
    );
