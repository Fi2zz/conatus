/// 子 Agent 的配置档案：由宿主按 `agent` 参数解析后交给 [SpawnAgentTool]。
library;

import 'package:conatus_llm/conatus_llm.dart';

import 'permissions/permission_rule.dart';
import 'sub_agent_permission.dart';

/// 一次 `spawn_agent` 委托使用的 Agent 配置。
///
/// [tools] 为 `null` 表示沿用宿主默认白名单（`spawn_agent` 未显式配置时为
/// 只读探索集）；非空时与请求的白名单取交集。宿主侧（nava 的
/// `AgentDefinition`）仅在作为主会话 Agent 时把 `null` 解释为「不额外限制」，
/// 子 Agent 路径统一以本类的默认白名单语义为准。[disabledTools] 在交集之后
/// 统一减去。权限规则只用于**收紧**：宿主已有的 deny / ask 不会被 profile 的
/// allow 放宽。
class SubAgentProfile {
  /// 创建档案。
  const SubAgentProfile({
    required this.id,
    required this.system,
    this.steps,
    this.tools,
    this.disabledTools = const <String>[],
    this.permissions = const <PermissionRule>[],
    this.llm,
    this.permissionMode = SubAgentPermission.inherit,
  });

  /// Agent ID。
  final String id;

  /// 子 Agent 的系统提示；空串时回落到宿主默认人设。
  final String system;

  /// 最大模型调用步数；`null` 表示沿用请求或工具默认值。
  final int? steps;

  /// 工具白名单；`null` 表示沿用宿主默认白名单。
  ///
  /// 空列表表示**禁止所有工具**（fail-closed）；非空时与请求的白名单取交集。
  final List<String>? tools;

  /// 显式禁用的工具（在交集之后减去）。
  final List<String> disabledTools;

  /// Agent 自带的权限规则；追加在宿主规则之后。
  final List<PermissionRule> permissions;

  /// Agent 指定的模型；`null` 表示沿用宿主模型。
  final LlmProvider? llm;

  /// 子代理权限模式的基档；模型请求只能在此基础上收紧。
  final SubAgentPermission permissionMode;
}

/// 按 Agent ID 解析 [SubAgentProfile]；找不到返回 `null`。
abstract class SubAgentProfileResolver {
  /// 解析 [agentId]；未知 ID 必须返回 `null`（调用方据此报告 UNKNOWN_AGENT）。
  Future<SubAgentProfile?> resolve(String agentId);
}
