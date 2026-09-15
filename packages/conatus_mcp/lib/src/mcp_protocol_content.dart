/// MCP 内容块与工具调用结果。
library;

import 'mcp_json.dart';

/// 一块内容：`text` / `image` / `audio` / `resource` 之一。
class McpContent {
  /// 直接构造。
  const McpContent({required this.type, this.text, this.data, this.mimeType});

  /// 从 JSON 解析；`type` 缺失时退回 `text`。
  factory McpContent.fromJson(Map<String, Object?> json) => McpContent(
        type: mcpString(json['type']) ?? 'text',
        text: mcpString(json['text']),
        data: json['data'],
        mimeType: mcpString(json['mimeType']),
      );

  /// 内容类型。
  final String type;

  /// 文本正文（`type == 'text'`）。
  final String? text;

  /// 二进制或资源负载（base64 字符串或资源对象）。
  final Object? data;

  /// MIME 类型；非文本内容一般都有。
  final String? mimeType;

  /// 序列化为 JSON。
  Map<String, Object?> toJson() => <String, Object?>{
        'type': type,
        if (text != null) 'text': text,
        if (data != null) 'data': data,
        if (mimeType != null) 'mimeType': mimeType,
      };
}

/// 把内容块拼成人可读文本：文本原样衔接（换行分隔），非文本给出占位说明。
///
/// 占位说明优先用 [McpContent.mimeType]（图片通常是 `[image/png]`），没有
/// MIME 时退回类型名（如 `[resource]`）；空文本块被跳过。
String describeMcpContent(List<McpContent> content) =>
    content.map(_describe).where((String line) => line.isNotEmpty).join('\n');

/// `tools/call` 的结果。
class McpToolResult {
  /// 直接构造；[failed] 对应线协议的 `isError`。
  const McpToolResult({
    this.content = const <McpContent>[],
    this.failed = false,
    this.structuredContent,
  });

  /// 从 JSON 解析，把线协议的 `isError` 映射到本地字段 [failed]。
  factory McpToolResult.fromJson(Map<String, Object?> json) => McpToolResult(
        content: _contents(json['content']),
        failed: json['isError'] == true,
        structuredContent: mcpMap(json['structuredContent']),
      );

  /// 结果内容块。
  final List<McpContent> content;

  /// 是否失败（线协议字段是 `isError`）。
  final bool failed;

  /// 结构化结果（可选，非标准扩展）。
  final Map<String, Object?>? structuredContent;
}

String _describe(McpContent block) {
  if (block.type == 'text') return block.text ?? '';
  return '[${block.mimeType ?? block.type}]';
}

List<McpContent> _contents(Object? raw) => <McpContent>[
      for (final Object? block in mcpList(raw))
        if (block is Map<String, Object?>) McpContent.fromJson(block),
    ];
