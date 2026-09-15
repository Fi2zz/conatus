/// skill 插件：把反复出现的工具序列沉淀为可命名、可复用的技能。
///
/// [SkillTool] 是一个普通 [Tool]：按序调用编排好的 [SkillStep]，支持把技能参数
/// 以 `{{name}}` 占位符注入每步参数。命名器见 `skill_namer.dart`，轨迹记录与
/// 提取见 `skill_library.dart`。
library;

import 'package:conatus_foundation/conatus_foundation.dart';

/// 技能里的一步：调用哪个工具、带什么参数（可含 `{{param}}` 占位符）。
class SkillStep {
  const SkillStep({
    required this.toolName,
    this.arguments = const <String, Object?>{},
  });

  /// 从 JSON 反序列化。
  factory SkillStep.fromJson(Map<String, Object?> json) => SkillStep(
        toolName: '${json['toolName'] ?? ''}',
        arguments: (json['arguments'] as Map?)?.cast<String, Object?>() ??
            const <String, Object?>{},
      );

  /// 工具名。
  final String toolName;

  /// 参数（字符串值里的 `{{name}}` 会被技能入参替换）。
  final Map<String, Object?> arguments;

  /// 序列化为 JSON。
  Map<String, Object?> toJson() =>
      <String, Object?>{'toolName': toolName, 'arguments': arguments};
}

/// 技能的命名与描述。
class SkillMeta {
  const SkillMeta({required this.name, required this.description});

  /// 技能名（工具名）。
  final String name;

  /// 技能描述。
  final String description;
}

/// 由「任务 + 工具序列」生成技能元信息。
typedef SkillNamer = Future<SkillMeta> Function(
    String task, List<String> tools);

/// 由工具序列派生出的技能。
class SkillTool extends Tool {
  SkillTool({
    required this.name,
    required this.description,
    required this.steps,
    required this.tools,
    List<ParamSpec>? params,
  }) : params = params ?? deriveSkillParams(steps);

  /// 技能名。
  @override
  final String name;

  /// 技能描述。
  @override
  final String description;

  /// 编排好的步骤。
  final List<SkillStep> steps;

  /// 执行步骤用的工具注册表。
  final ToolRegistry tools;

  /// 技能参数（由 `{{name}}` 占位符派生，除非显式传入）。
  @override
  final List<ParamSpec> params;

  @override
  ToolRisk get riskLevel => ToolRisk.medium;

  @override
  Future<ToolResult> call(ToolContext ctx) async {
    final List<Object?> outputs = <Object?>[];
    for (final SkillStep step in steps) {
      final Map<String, Object?> args = <String, Object?>{
        for (final MapEntry<String, Object?> entry in step.arguments.entries)
          entry.key: resolveSkillArg(entry.value, ctx.arguments),
      };
      final ToolResult result =
          await tools.call(ToolCall(name: step.toolName, arguments: args));
      if (result.isError) {
        return ToolResult.failure(
          '技能 "$name" 在步骤 ${step.toolName} 失败：${result.content}',
          error: result.error,
        );
      }
      outputs.add(result.content);
    }
    return ToolResult.success(
      outputs.isEmpty ? '' : '${outputs.last}',
      value: outputs,
    );
  }

  /// 序列化为可持久化的记录。
  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        'description': description,
        'steps': <Map<String, Object?>>[
          for (final SkillStep step in steps) step.toJson(),
        ],
      };

  /// 从记录恢复。
  static SkillTool fromJson(Map<String, Object?> json, ToolRegistry tools) =>
      SkillTool(
        name: '${json['name'] ?? ''}',
        description: '${json['description'] ?? ''}',
        steps: <SkillStep>[
          for (final Object? item
              in (json['steps'] as List<Object?>?) ?? const <Object?>[])
            if (item is Map)
              SkillStep.fromJson(Map<String, Object?>.from(item)),
        ],
        tools: tools,
      );
}

/// 扫描步骤参数里的 `{{name}}` 占位符，派生必填字符串参数。
List<ParamSpec> deriveSkillParams(List<SkillStep> steps) {
  final Set<String> names = <String>{};
  for (final SkillStep step in steps) {
    for (final Object? value in step.arguments.values) {
      if (value is! String) continue;
      for (final RegExpMatch match
          in RegExp(r'\{\{(\w+)\}\}').allMatches(value)) {
        names.add(match.group(1)!);
      }
    }
  }
  return <ParamSpec>[
    for (final String name in names) ParamSpec.string(name, required: true),
  ];
}

/// 把字符串里的 `{{name}}` 用技能入参替换；非字符串原样返回。
Object? resolveSkillArg(Object? value, Map<String, Object?> args) {
  if (value is! String) return value;
  return value.replaceAllMapped(
    RegExp(r'\{\{(\w+)\}\}'),
    (Match match) => '${args[match.group(1)!] ?? match.group(0)}',
  );
}
