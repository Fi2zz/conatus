/// MCP 提示词词汇：`prompts/list` 的模板与 `prompts/get` 填充后的消息。
library;

import 'mcp_json.dart';
import 'mcp_protocol_content.dart';

/// 一台 server 暴露的提示词模板。
class McpPrompt {
  /// 直接构造。
  const McpPrompt({
    required this.name,
    this.description,
    this.arguments = const <McpPromptArgument>[],
  });

  /// 从 JSON 解析；`name` 缺失时为空串。
  factory McpPrompt.fromJson(Map<String, Object?> json) => McpPrompt(
        name: mcpString(json['name']) ?? '',
        description: mcpString(json['description']),
        arguments: <McpPromptArgument>[
          for (final Object? item in mcpList(json['arguments']))
            if (item is Map<String, Object?>) McpPromptArgument.fromJson(item),
        ],
      );

  /// 提示词名（在 server 内唯一）。
  final String name;

  /// 面向模型的简介（可选）。
  final String? description;

  /// 参数声明；无参时为空表。
  final List<McpPromptArgument> arguments;
}

/// 提示词的一个参数声明。
class McpPromptArgument {
  /// 直接构造。
  const McpPromptArgument({
    required this.name,
    this.description,
    this.required = false,
  });

  /// 从 JSON 解析；缺 `required` 按非必填处理。
  factory McpPromptArgument.fromJson(Map<String, Object?> json) =>
      McpPromptArgument(
        name: mcpString(json['name']) ?? '',
        description: mcpString(json['description']),
        required: json['required'] == true,
      );

  /// 参数名。
  final String name;

  /// 参数说明（可选）。
  final String? description;

  /// 是否必填。
  final bool required;
}

/// `prompts/get` 返回的一条消息：只保留角色与文本。
class McpPromptMessage {
  /// 直接构造。
  const McpPromptMessage({required this.role, required this.text});

  /// 从 JSON 解析；非文本内容按 `[mimeType]` 占位，与工具结果同一套规则。
  ///
  /// `content` 既接受单个内容块，也接受内容块数组；`role` 缺失时按 `user`。
  factory McpPromptMessage.fromJson(Map<String, Object?> json) =>
      McpPromptMessage(
        role: mcpString(json['role']) ?? 'user',
        text: describeMcpContent(_contentsOf(json['content'])),
      );

  /// 消息角色（`user` / `assistant`）。
  final String role;

  /// 拼好的文本正文。
  final String text;
}

List<McpContent> _contentsOf(Object? raw) {
  final Map<String, Object?>? single = mcpMap(raw);
  if (single != null) return <McpContent>[McpContent.fromJson(single)];
  return <McpContent>[
    for (final Object? item in mcpList(raw))
      if (item is Map<String, Object?>) McpContent.fromJson(item),
  ];
}
