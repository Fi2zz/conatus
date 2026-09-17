/// 顺序协作模式：成员 A → B → C，每个处理上一个的输出。
///
/// 适用场景：分阶段处理，每阶段依赖上一阶段结论（如「调研 → 起草 → 审校」）。
/// [options]['members'] 提供成员名清单；按顺序 spawn + ask，上一轮 reply
/// 作为下一轮输入。
library;

import 'dart:async';

import '../agent_team.dart';
import '../team_pattern.dart';
import '../teammate.dart';

/// 顺序模式：A 的输出是 B 的输入，B 的输出是 C 的输入。
class SequentialPattern implements TeamPattern {
  const SequentialPattern({this.maxMembers = 8});

  /// 单次执行最多 spawn 的成员数（安全阀）。
  final int maxMembers;

  @override
  String get name => 'sequential';

  @override
  Future<Object?> execute({
    required AgentTeam team,
    required String input,
    Map<String, Object?> options = const <String, Object?>{},
  }) async {
    final List<String> members = _asNames(options['members']);
    final int limit = maxMembers < members.length ? maxMembers : members.length;
    String current = input;
    for (int i = 0; i < limit; i++) {
      final Teammate m = await team.spawn(name: members[i]);
      current = await team.ask(m.id, current);
    }
    return current;
  }

  List<String> _asNames(Object? raw) {
    if (raw is! List) return const <String>[];
    return <String>[for (final Object? n in raw) '$n'];
  }
}
