/// memory 工具：把「显式记住 / 显式遗忘」能力暴露给模型。
///
/// 能力本体在 [MemoryStore]（`ctx.memory`，用户/宿主可直接调用）；本文件的
/// [RememberTool] / [ForgetTool] 只是给模型用的工具壳，二者调用同一能力：
///
/// ```dart
/// // 宿主 / 用户直接调用能力（不经模型）
/// await ctx.memory.remember('用户喜欢京剧', tags: {'偏好'});
/// await ctx.memory.forgetByText('用户喜欢京剧');
/// await ctx.memory.forgetMatching('京剧');
/// await ctx.memory.forget(id);
/// ```
library;

import 'package:conatus_core/conatus_core.dart';
import 'memory.dart';
import 'memory_types.dart';
import 'tools.dart';

/// 显式记住一段文本的工具。
class RememberTool extends Tool {
  RememberTool({
    required MemoryStore memory,
    Set<String> tags = const <String>{},
  })  : _memory = memory,
        _tags = tags;

  final MemoryStore _memory;

  /// 每次记住时附加的固定标签。
  final Set<String> _tags;

  @override
  String get name => 'remember';

  @override
  String get description => '显式记住一段信息（可带标签），供后续召回。';

  @override
  ToolRisk get riskLevel => ToolRisk.medium;

  @override
  List<ParamSpec> get params => <ParamSpec>[
        ParamSpec.string('text', required: true, description: '要记住的内容'),
        ParamSpec.array(
          'tags',
          items: ParamSpec.string('tag'),
          description: '可选标签',
        ),
      ];

  @override
  Future<ToolResult> call(ToolContext context) async {
    final String text = context.str('text').trim();
    if (text.isEmpty) {
      return ToolResult.failure(
        '要记住的内容不能为空',
        error: const ToolError('EMPTY_TEXT', 'empty text'),
      );
    }
    final Set<String> tags = <String>{
      ..._tags,
      for (final Object? tag in context.array('tags') ?? const <Object?>[])
        '$tag',
    };
    final MemoryEntry entry = await _memory.remember(text, tags: tags);
    return ToolResult.success(
      '已记住（id=${entry.id}）。',
      value: <String, Object?>{
        'id': entry.id,
        'text': entry.text,
        'tags': entry.tags.toList(growable: false),
      },
    );
  }
}

/// 显式遗忘记忆的工具。
class ForgetTool extends Tool {
  ForgetTool({required MemoryStore memory}) : _memory = memory;

  final MemoryStore _memory;

  @override
  String get name => 'forget';

  @override
  String get description => '显式遗忘记忆：按 id 精确删除一条，或按 text 删除正文包含该文本的记忆。';

  @override
  ToolRisk get riskLevel => ToolRisk.medium;

  @override
  List<ParamSpec> get params => <ParamSpec>[
        ParamSpec.string('id', description: '要删除的记忆 id'),
        ParamSpec.string('text', description: '要删除的记忆正文关键字（包含匹配）'),
      ];

  @override
  Future<ToolResult> call(ToolContext context) async {
    final String? id = _nonEmpty(context.string('id'));
    final String? text = _nonEmpty(context.string('text'));
    if ((id == null) == (text == null)) {
      return ToolResult.failure(
        '请且仅请提供 id 或 text 之一',
        error:
            const ToolError('INVALID_ARGS', 'provide exactly one of id/text'),
      );
    }

    if (id != null) {
      final bool removed = await _memory.forget(id);
      if (!removed) {
        return ToolResult.failure(
          '未找到 id="$id" 的记忆',
          error: const ToolError('MEMORY_NOT_FOUND', 'memory not found'),
        );
      }
      return ToolResult.success(
        '已遗忘 id="$id"。',
        value: <String, Object?>{
          'deleted': 1,
          'ids': <String>[id]
        },
      );
    }

    final int deleted = await _memory.forgetMatching(text!);
    if (deleted == 0) {
      return ToolResult.failure(
        '没有正文包含 "$text" 的记忆',
        error: const ToolError('MEMORY_NOT_FOUND', 'memory not found'),
      );
    }
    return ToolResult.success(
      '已遗忘 $deleted 条记忆。',
      value: <String, Object?>{'deleted': deleted},
    );
  }
}

String? _nonEmpty(String? value) {
  final String trimmed = value?.trim() ?? '';
  return trimmed.isEmpty ? null : trimmed;
}

/// 注册 [RememberTool] 到 `ctx.tools`，返回已注册的工具。
///
/// [memory] 缺省取上下文的 `'memory'` 服务；[tools] 缺省取 `ctx.tools`。
List<Tool> provideRememberTool(
  Context ctx, {
  MemoryStore? memory,
  ToolRegistry? tools,
  Set<String> tags = const <String>{},
}) {
  final MemoryStore resolved = memory ?? ctx.require<MemoryStore>('memory');
  final ToolRegistry registry = tools ?? ctx.tools;
  final Tool tool = RememberTool(memory: resolved, tags: tags);
  ctx.effect(() => registry.register(tool));
  return <Tool>[tool];
}

/// 注册 [ForgetTool] 到 `ctx.tools`，返回已注册的工具。
List<Tool> provideForgetTool(
  Context ctx, {
  MemoryStore? memory,
  ToolRegistry? tools,
}) {
  final MemoryStore resolved = memory ?? ctx.require<MemoryStore>('memory');
  final ToolRegistry registry = tools ?? ctx.tools;
  final Tool tool = ForgetTool(memory: resolved);
  ctx.effect(() => registry.register(tool));
  return <Tool>[tool];
}

/// 一次性注册记住 / 遗忘两个工具，返回已注册的工具。
List<Tool> provideMemoryTools(
  Context ctx, {
  MemoryStore? memory,
  ToolRegistry? tools,
}) {
  final MemoryStore resolved = memory ?? ctx.require<MemoryStore>('memory');
  final ToolRegistry registry = tools ?? ctx.tools;
  final List<Tool> registered = <Tool>[
    RememberTool(memory: resolved),
    ForgetTool(memory: resolved),
  ];
  for (final Tool tool in registered) {
    ctx.effect(() => registry.register(tool));
  }
  return registered;
}
