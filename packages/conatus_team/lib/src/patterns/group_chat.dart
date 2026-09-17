/// 群聊协作模式：多个成员共享对话历史，轮流发言直到收敛。
///
/// 与顺序 / 并发的本质区别：成员能看到彼此的发言。由于成员持独立
/// [Session]，群聊通过把累计历史作为 [AgentTeam.ask] 的 message 传入
/// 实现——每轮把之前的发言拼成上下文喂给当前发言者。
///
/// [options]['members'] 提供成员名清单；['maxRounds'] 控制最大轮次
/// （默认 10）。收敛判定：reply 含「done / 完成 / 结论」关键词，或
/// 达到 maxRounds。返回最后一条发言。
library;

import 'dart:async';

import '../agent_team.dart';
import '../team_pattern.dart';
import '../teammate.dart';

/// 群聊模式：成员共享历史，轮流发言直到收敛。
class GroupChatPattern implements TeamPattern {
  const GroupChatPattern({this.defaultMaxRounds = 10});

  /// 缺省最大轮次。
  final int defaultMaxRounds;

  @override
  String get name => 'group_chat';

  @override
  Future<Object?> execute({
    required AgentTeam team,
    required String input,
    Map<String, Object?> options = const <String, Object?>{},
  }) async {
    final List<String> names = _asNames(options['members']);
    final int maxRounds = _asInt(options['maxRounds'], defaultMaxRounds);
    if (names.isEmpty) return input;
    final List<Teammate> members = <Teammate>[];
    for (final String n in names) {
      members.add(await team.spawn(name: n));
    }
    final List<String> history = <String>[input];
    for (int round = 0; round < maxRounds; round++) {
      final Teammate speaker = members[round % members.length];
      final String message = history.join('\n---\n');
      final String reply = await team.ask(speaker.id, message);
      history.add('${speaker.name}: $reply');
      if (_converged(reply)) break;
    }
    return history.last;
  }

  /// 收敛判定：否定优先——显式否定短语或否定词修饰的收敛词不算收敛。
  bool _converged(String reply) {
    final String lower = reply.toLowerCase();
    if (lower.contains('not done') ||
        lower.contains('not yet done') ||
        lower.contains('cannot agree')) {
      return false;
    }
    if (_negatedBeforeKeyword(reply)) return false;
    return lower.contains('done') ||
        reply.contains('完成') ||
        reply.contains('结论') ||
        reply.contains('同意');
  }

  /// 否定词紧邻收敛词（如「还没结论」「未完成」「不同意」）时不收敛。
  bool _negatedBeforeKeyword(String text) => RegExp(
          r'(没|未|无|不)[^，。！？,.;!?]{0,4}(结论|完成|同意)')
      .hasMatch(text);

  List<String> _asNames(Object? raw) {
    if (raw is! List) return const <String>[];
    return <String>[for (final Object? n in raw) '$n'];
  }

  int _asInt(Object? raw, int fallback) {
    if (raw is int) return raw;
    if (raw is String) return int.tryParse(raw) ?? fallback;
    return fallback;
  }
}
