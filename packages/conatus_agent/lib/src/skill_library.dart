/// skill-library：记录工具轨迹、按重复次数提取技能、注册并持久化。
/// 同一工具序列出现 [threshold] 次后用 [SkillNamer] 命名并构造 [SkillTool] 注册；
/// 含 `high` 风险步骤的序列不沉淀；启用前若配了 [Approval] 需先获批；技能可存进
/// [MemoryStore] 跨会话恢复。
library;

import 'dart:convert';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'agent_types.dart';
import 'approval.dart';
import 'skill.dart';
import 'skill_namer.dart';

class _Trace {
  const _Trace(this.task, this.steps);
  final String task;
  final List<SkillStep> steps;
}

/// 技能库：轨迹 → 提取 → 注册 → 持久化。
class SkillLibrary {
  SkillLibrary({this.threshold = 3, this.namer, this.approval, this.memory}) {
    if (threshold < 1) {
      throw ArgumentError.value(threshold, 'threshold', '必须为正整数');
    }
  }

  /// 触发提取的重复次数。
  final int threshold;

  /// 命名器（默认由 `provideSkillLibrary` 用 LLM 装配，缺省确定性命名）。
  final SkillNamer? namer;

  /// 启用新技能前的审批端口；null 表示免审批。
  final Approval? approval;

  /// 技能持久化用的长记忆库；null 表示不持久化。
  final MemoryStore? memory;

  final List<_Trace> _traces = <_Trace>[];
  final List<SkillTool> _skills = <SkillTool>[];
  final Set<String> _extracted = <String>{};

  /// 已沉淀的技能。
  List<SkillTool> get skills => List<SkillTool>.unmodifiable(_skills);

  /// 已记录的轨迹数。
  int get traceCount => _traces.length;

  /// 记录一条成功轨迹。
  void record(String task, List<SkillStep> steps) {
    if (steps.isEmpty) return;
    _traces.add(_Trace(task, steps));
  }

  /// 便捷记录：只有工具名的轨迹。
  void recordTools(String task, Iterable<String> tools) =>
      record(task, <SkillStep>[
        for (final String tool in tools) SkillStep(toolName: tool),
      ]);

  /// 若某条工具序列达到阈值且可用，提取并注册技能；否则返回 null。
  Future<SkillTool?> maybeExtract({
    required ToolRegistry tools,
    SkillNamer? namer,
  }) async {
    final _Trace? trace = _firstRepeat();
    if (trace == null) return null;
    final String signature = _signature(trace.steps);
    _extracted.add(signature);
    if (!_isSafe(trace.steps, tools)) return null;

    final List<String> names = <String>[
      for (final SkillStep step in trace.steps) step.toolName,
    ];
    final SkillNamer resolved = namer ?? this.namer ?? deterministicSkillNamer;
    final SkillMeta meta = await resolved(trace.task, names);
    final SkillTool skill = SkillTool(
      name: meta.name,
      description: meta.description,
      steps: trace.steps,
      tools: tools,
    );
    final Approval? gate = approval;
    if (gate != null) {
      final bool approved = await gate.request(ApprovalRequest(
        id: 'skill-${DateTime.now().microsecondsSinceEpoch}',
        toolName: 'skill:${skill.name}',
        description: skill.description,
      ));
      if (!approved) return null;
    }
    if (tools.get(skill.name) == null) tools.register(skill);
    _skills.add(skill);
    await _persist(skill);
    return skill;
  }

  /// 把已沉淀技能写入长记忆。
  Future<void> _persist(SkillTool skill) async {
    final MemoryStore? store = memory;
    if (store == null) return;
    await store.remember(jsonEncode(skill.toJson()), tags: <String>{'skill'});
  }

  /// 从长记忆恢复已持久化的技能并注册；返回恢复数量。
  Future<int> restore(
      {required ToolRegistry tools, MemoryStore? memory}) async {
    final MemoryStore? store = memory ?? this.memory;
    if (store == null) return 0;
    await store.load();
    int restored = 0;
    for (final MemoryEntry entry
        in store.entries.where((MemoryEntry e) => e.tags.contains('skill'))) {
      try {
        final Object? decoded = jsonDecode(entry.text);
        if (decoded is! Map) continue;
        final SkillTool skill =
            SkillTool.fromJson(Map<String, Object?>.from(decoded), tools);
        if (skill.name.isEmpty || tools.get(skill.name) != null) continue;
        tools.register(skill);
        _skills.add(skill);
        restored++;
      } on FormatException {
        // 损坏的记忆跳过。
      }
    }
    return restored;
  }

  _Trace? _firstRepeat() {
    final Map<String, int> counts = <String, int>{};
    for (final _Trace trace in _traces) {
      final String signature = _signature(trace.steps);
      if (_extracted.contains(signature)) continue;
      final int count = (counts[signature] ?? 0) + 1;
      counts[signature] = count;
      if (count >= threshold) return trace;
    }
    return null;
  }

  bool _isSafe(List<SkillStep> steps, ToolRegistry tools) {
    for (final SkillStep step in steps) {
      final Tool? tool = tools.get(step.toolName);
      if (tool == null || tool.riskLevel == ToolRisk.high) return false;
    }
    return true;
  }

  static String _signature(List<SkillStep> steps) =>
      steps.map((SkillStep s) => s.toolName).join('>');
}

/// 从会话事件里的 `tool/result` 提取工具名序列（用于技能沉淀）。
List<String> toolNamesFromEvents(Iterable<SessionEvent> events) => <String>[
      for (final SessionEvent event in events)
        if (event.type == kToolResultEvent && event.data is Map)
          '${(event.data! as Map)['name'] ?? ''}',
    ];

/// `ctx.skills`：当前上下文可见的技能库。
extension SkillContext on Context {
  /// 取当前上下文可见的 [SkillLibrary]（未提供时抛 [StateError]）。
  SkillLibrary get skills => require<SkillLibrary>('skill');
}

/// 提供 `'skill'` 服务并从长记忆恢复已沉淀技能，返回技能库。
///
/// 命名器优先用显式 [namer]，否则用 [llm]（或上下文 `'llm'`）装配
/// [llmSkillNamer]，再否则为确定性命名。审批与记忆缺省取上下文服务。
SkillLibrary provideSkillLibrary(
  Context ctx, {
  SkillLibrary? library,
  LlmProvider? llm,
  ToolRegistry? tools,
  MemoryStore? memory,
  Approval? approval,
  int threshold = 3,
  SkillNamer? namer,
}) {
  final MemoryStore? store = memory ?? ctx.get<MemoryStore>('memory');
  final LlmProvider? model = llm ?? ctx.get<LlmProvider>('llm');
  final SkillNamer resolvedNamer =
      namer ?? (model == null ? deterministicSkillNamer : llmSkillNamer(model));
  final SkillLibrary instance = library ??
      SkillLibrary(
        threshold: threshold,
        namer: resolvedNamer,
        approval: approval ?? ctx.get<Approval>('approval'),
        memory: store,
      );
  ctx.provide('skill', instance);
  return instance;
}
