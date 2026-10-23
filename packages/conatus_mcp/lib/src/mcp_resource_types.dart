/// MCP 资源词汇：`resources/list`、`resources/templates/list` 与
/// `resources/read`。
///
/// 解析一律宽松：字段缺失或类型不对退回缺省值，不打断整条消息。
library;

import 'mcp_json.dart';

/// 一台 server 暴露的资源（一个可直接读取的 URI）。
class McpResource {
  /// 直接构造。
  const McpResource({
    required this.uri,
    required this.name,
    this.description,
    this.mimeType,
  });

  /// 从 JSON 解析；`uri` / `name` 缺失时为空串（服务端异常形态）。
  factory McpResource.fromJson(Map<String, Object?> json) => McpResource(
        uri: mcpString(json['uri']) ?? '',
        name: mcpString(json['name']) ?? '',
        description: mcpString(json['description']),
        mimeType: mcpString(json['mimeType']),
      );

  /// 资源 URI（如 `file:///tmp/a.txt`）。
  final String uri;

  /// 展示名。
  final String name;

  /// 面向模型的简介（可选）。
  final String? description;

  /// MIME 类型（可选）。
  final String? mimeType;
}

/// 资源模板：一个带占位符的 URI 形态（如 `file:///{path}`）。
class McpResourceTemplate {
  /// 直接构造。
  const McpResourceTemplate({
    required this.uriTemplate,
    required this.name,
    this.description,
    this.mimeType,
  });

  /// 从 JSON 解析；RFC 6570 的 `uriTemplate` 缺失时为空串。
  factory McpResourceTemplate.fromJson(Map<String, Object?> json) =>
      McpResourceTemplate(
        uriTemplate: mcpString(json['uriTemplate']) ?? '',
        name: mcpString(json['name']) ?? '',
        description: mcpString(json['description']),
        mimeType: mcpString(json['mimeType']),
      );

  /// URI 模板（RFC 6570）。
  final String uriTemplate;

  /// 展示名。
  final String name;

  /// 面向模型的简介（可选）。
  final String? description;

  /// MIME 类型（可选）。
  final String? mimeType;
}

/// `resources/read` 返回的一块内容：文本 [text] 或 base64 二进制 [blob]。
class McpResourceContents {
  /// 直接构造。
  const McpResourceContents({
    required this.uri,
    this.mimeType,
    this.text,
    this.blob,
  });

  /// 从 JSON 解析；[text] 与 [blob] 互斥，按服务端给的形态保留。
  factory McpResourceContents.fromJson(Map<String, Object?> json) =>
      McpResourceContents(
        uri: mcpString(json['uri']) ?? '',
        mimeType: mcpString(json['mimeType']),
        text: mcpString(json['text']),
        blob: mcpString(json['blob']),
      );

  /// 内容所属的资源 URI。
  final String uri;

  /// MIME 类型（可选）。
  final String? mimeType;

  /// 文本正文；二进制内容为 `null`。
  final String? text;

  /// base64 编码的二进制正文；文本内容为 `null`。
  final String? blob;
}
