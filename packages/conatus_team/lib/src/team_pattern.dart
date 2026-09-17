/// 协作模式接口：策略层，复用 [AgentTeam] 机制。
///
/// 模式与机制分离：[AgentTeam] 只提供成员生命周期 / 消息系统 / 任务板，
/// 模式决定「谁创建谁、谁跟谁说话、什么时候停」。本包内置四种模式
/// （顺序 / 并发 / 群聊 / Maker-Checker），用户也可自实现 [TeamPattern]。
///
/// 模式通过 [execute] 接收 [input] 与 [options]，调度 [team] 完成
/// 协作，返回最终结果。模式不持有状态，每次 [execute] 都是一次
/// 独立运行。
library;

import 'dart:async';

import 'agent_team.dart';

/// 协作模式端口。
abstract class TeamPattern {
  /// 模式名（如 'sequential' / 'concurrent' / 'group_chat' / 'maker_checker'）。
  String get name;

  /// 在 [team] 上执行一轮协作。
  ///
  /// - [input]：初始输入（任务描述 / 用户问题）。
  /// - [options]：模式特定参数（如成员名清单、最大轮次）。
  ///
  /// 返回协作的最终结果；无结果时返回 null。
  Future<Object?> execute({
    required AgentTeam team,
    required String input,
    Map<String, Object?> options = const <String, Object?>{},
  });
}
