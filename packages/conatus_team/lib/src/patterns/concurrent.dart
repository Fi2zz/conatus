/// 并发协作模式：多个成员同时处理同一输入，全部完成后汇总。
///
/// 适用场景：多视角审查（性能 / 安全 / 产品）、多路径探索。所有成员
/// 收到相同 [input]，并发 [AgentTeam.ask]，[Future.wait] 等全部完成。
/// [options]['members'] 提供成员名清单；返回每个成员的 reply 列表。
library;

import 'dart:async';

import '../agent_team.dart';
import '../team_pattern.dart';
import '../teammate.dart';

/// 并发模式：所有成员同时处理同一输入，返回 reply 列表。
class ConcurrentPattern implements TeamPattern {
  const ConcurrentPattern({this.maxMembers = 8});

  /// 单次执行最多 spawn 的成员数（安全阀）。
  final int maxMembers;

  @override
  String get name => 'concurrent';

  @override
  Future<Object?> execute({
    required AgentTeam team,
    required String input,
    Map<String, Object?> options = const <String, Object?>{},
  }) async {
    final List<String> names = _asNames(options['members']);
    final int limit = maxMembers < names.length ? maxMembers : names.length;
    final List<Teammate> members = <Teammate>[];
    for (int i = 0; i < limit; i++) {
      members.add(await team.spawn(name: names[i]));
    }
    final List<String> replies = await Future.wait(
        members.map((Teammate m) => team.ask(m.id, input)));
    return replies;
  }

  List<String> _asNames(Object? raw) {
    if (raw is! List) return const <String>[];
    return <String>[for (final Object? n in raw) '$n'];
  }
}
