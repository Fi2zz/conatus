part of 'mcp_resource_tools.dart';

ToolResult _unknownServer(String server) => ToolResult.failure(
      '未知 MCP server "$server"',
      error: ToolError('MCP_SERVER_UNKNOWN', 'unknown server "$server"'),
    );

/// 文本优先：`text` 字段存在即按文本输出（不看 MIME——服务端可能把
/// `application/json` 这类文本放在 `text` 里）；否则把 `blob` 当二进制，
/// 只报解码后的字节数。
String _render(McpResourceContents content) {
  final String? text = content.text;
  if (text != null) return _capText(text);
  final String? blob = content.blob;
  if (blob == null) return '（空内容）';
  return '[binary ${_blobLength(blob)} bytes]';
}

/// 按 base64 长度估算原始字节数，不解码整段载荷。
int _blobLength(String blob) {
  final String clean = blob.replaceAll(RegExp(r'\s'), '');
  final int padding = clean.endsWith('==')
      ? 2
      : clean.endsWith('=')
          ? 1
          : 0;
  final int length = (clean.length * 3) ~/ 4 - padding;
  return length < 0 ? 0 : length;
}

/// 按 UTF-8 字节上限截断到完整字符边界，避免产出 U+FFFD。
String _capText(String text) {
  final List<int> bytes = utf8.encode(text);
  if (bytes.length <= kMcpResourceContentLimit) return text;
  final int end = _safeCut(bytes, kMcpResourceContentLimit);
  return '${utf8.decode(bytes.sublist(0, end))}…（已截断）';
}

/// 把 [limit] 退回完整 UTF-8 字符边界（最多退 3 字节）。
int _safeCut(List<int> bytes, int limit) {
  int lead = limit - 1;
  while (lead >= 0 && (bytes[lead] & 0xC0) == 0x80) {
    lead--;
  }
  if (lead < 0) return 0;
  final int first = bytes[lead];
  final int needed = first >= 0xF0
      ? 4
      : first >= 0xE0
          ? 3
          : first >= 0xC0
              ? 2
              : 1;
  return lead + needed > limit ? lead : limit;
}

String? _blankToNull(String? value) {
  final String? trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
