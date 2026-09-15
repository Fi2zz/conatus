/// MCP 工具声明：`tools/list` 返回的单个工具。
library;

import 'mcp_json.dart';

/// 一台 server 暴露的工具。
class McpTool {
  /// 直接构造。
  const McpTool({
    required this.name,
    this.title,
    this.description,
    this.inputSchema = const <String, Object?>{},
    this.annotations = const <String, Object?>{},
    this.riskLevel,
  });

  /// 从 JSON 解析；宽松处理，缺失字段退回缺省值。
  ///
  /// `name` 缺失时为空串（服务端异常形态），上层适配器仍能注册，只是名不好看。
  factory McpTool.fromJson(Map<String, Object?> json) => McpTool(
        name: mcpString(json['name']) ?? '',
        title: mcpString(json['title']),
        description: mcpString(json['description']),
        inputSchema: mcpMap(json['inputSchema']) ?? const <String, Object?>{},
        annotations: mcpMap(json['annotations']) ?? const <String, Object?>{},
        riskLevel: mcpString(json['riskLevel']),
      );

  /// 工具名（在 server 内唯一）。
  final String name;

  /// 展示名（可选）。
  final String? title;

  /// 面向模型的简介。
  final String? description;

  /// 入参的 JSON Schema；由服务端下发，客户端原样透传给模型。
  final Map<String, Object?> inputSchema;

  /// MCP 标准的注解：
  ///
  /// * `readOnlyHint` — 只读，不改变外部世界；
  /// * `destructiveHint` — 可能破坏性，需要强确认；
  /// * `idempotentHint` — 重复调用等效；
  /// * `openWorldHint` — 触及开放世界（网络等）。
  final Map<String, Object?> annotations;

  /// **非标准扩展字段**：服务端自行声明的风险等级标签
  /// （如 `readonly` / `write` / `destructive`），大小写不敏感。
  final String? riskLevel;
}
