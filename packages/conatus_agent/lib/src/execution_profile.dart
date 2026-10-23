/// 按任务特征选择执行档位：档位 = reasoning effort + 工具预算策略。
///
/// 选择器只在显式装配时生效；超时、异常、未知档位名一律返回 `null`，由调用方
/// 落回默认档，绝不阻断主流程。
library;

import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'execution_profile_rubric.dart';
import 'tool_budget_policy.dart';

/// 一个执行档位。
class ExecutionProfile {
  const ExecutionProfile({
    required this.name,
    required this.reasoningEffort,
    required this.budget,
  });

  /// 档位名（与 rubric 输出一致）。
  final String name;

  /// 推理强度（`low` / `medium` / `high`），由调用方透传给模型。
  final String reasoningEffort;

  /// 该档位的工具预算策略。
  final ToolBudgetPolicy budget;
}

/// 默认档位表：阈值属于本项目标定，非论文数字。
const Map<String, ExecutionProfile> kDefaultExecutionProfiles =
    <String, ExecutionProfile>{
  'compact': ExecutionProfile(
    name: 'compact',
    reasoningEffort: 'low',
    budget: ToolBudgetPolicy(
        economyAfter: 2, strictAfter: 4, finalizeAfter: 14),
  ),
  'lean': ExecutionProfile(
    name: 'lean',
    reasoningEffort: 'low',
    budget: ToolBudgetPolicy(
        economyAfter: 6, strictAfter: 10, finalizeAfter: 22),
  ),
  'standard': ExecutionProfile(
    name: 'standard',
    reasoningEffort: 'medium',
    budget: ToolBudgetPolicy(),
  ),
  'deep': ExecutionProfile(
    name: 'deep',
    reasoningEffort: 'high',
    budget: ToolBudgetPolicy(
        economyAfter: 16, strictAfter: 30, finalizeAfter: 54),
  ),
  'research': ExecutionProfile(
    name: 'research',
    reasoningEffort: 'high',
    budget: ToolBudgetPolicy(
        economyAfter: 8, strictAfter: 20, finalizeAfter: 46),
  ),
};

/// 档位选择端口。
abstract interface class ProfileSelector {
  /// 为 [task] 选一个档位；无法判断时返回 `null`。
  Future<ExecutionProfile?> select(String task);
}

/// 用一次 tool-free 小调用读 rubric 选档。
class LlmProfileSelector implements ProfileSelector {
  LlmProfileSelector(
    this.llm,
    this.profiles, {
    this.timeout = const Duration(seconds: 15),
    this.maxTaskChars = 24000,
  });

  /// 选择用的模型。
  final LlmProvider llm;

  /// 档位表；决定哪些名字合法。
  final Map<String, ExecutionProfile> profiles;

  /// 单次选择超时。
  final Duration timeout;

  /// 任务文本截断长度（字符）。
  final int maxTaskChars;

  @override
  Future<ExecutionProfile?> select(String task) async {
    if (profiles.isEmpty) return null;
    final String clipped =
        task.length > maxTaskChars ? task.substring(0, maxTaskChars) : task;
    try {
      final LlmResult reply = await llm
          .chat(<LlmMessage>[
            const LlmMessage('system', kExecutionProfileRubric),
            LlmMessage('user', clipped),
          ], options: <String, dynamic>{'max_output_tokens': 256})
          .timeout(timeout);
      return matchProfile(reply.content);
    } catch (_) {
      return null;
    }
  }

  /// 在回复里按词边界找一个合法档位名；找不到返回 `null`。
  ExecutionProfile? matchProfile(String text) {
    final Set<String> tokens = text
        .toLowerCase()
        .split(RegExp('[^a-z0-9_]+'))
        .where((String token) => token.isNotEmpty)
        .toSet();
    for (final MapEntry<String, ExecutionProfile> entry in profiles.entries) {
      if (tokens.contains(entry.key.toLowerCase())) return entry.value;
    }
    return null;
  }
}

/// 装配档位选择器；缺模型或缺档位表时返回 `null`（等于关闭）。
ProfileSelector? provideProfileSelector(
  Context ctx, {
  ProfileSelector? selector,
  LlmProvider? llm,
  Map<String, ExecutionProfile>? profiles,
}) {
  final ProfileSelector? resolved =
      selector ?? _buildSelector(ctx, llm, profiles);
  if (resolved == null) return null;
  ctx.provide('profileSelector', resolved);
  return resolved;
}

ProfileSelector? _buildSelector(
  Context ctx,
  LlmProvider? llm,
  Map<String, ExecutionProfile>? profiles,
) {
  final LlmProvider? provider = llm ?? ctx.get<LlmProvider>('llm');
  final Map<String, ExecutionProfile>? table = profiles ??
      ctx.get<Map<String, ExecutionProfile>>('executionProfiles');
  if (provider == null || table == null || table.isEmpty) return null;
  return LlmProfileSelector(provider, table);
}
