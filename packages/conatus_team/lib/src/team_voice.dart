/// 团队语音播报 seam：把团队事件转成 TTS 文案。
///
/// conatus_team 不直接依赖 conatus_tts，通过本抽象注入。装配方在
/// 主程序侧用 TTS 适配 [TeamVoice.say]；文案生成是纯函数，可独立
/// 测试。语音审批（[HANDOFF-6] §11.5）由装配方把 [AskUserApproval]
/// 的语音版注入 [TeamHooks.approval]——本包不感知。
library;

import 'agent_team.dart';
import 'teammate.dart';

/// 团队语音播报端口。
abstract class TeamVoice {
  /// 播报一句话。
  void say(String text);

  /// 不播报的单例。
  static const TeamVoice noop = _NoopVoice();
}

class _NoopVoice implements TeamVoice {
  const _NoopVoice();
  @override
  void say(String text) {}
}

/// 团队创建播报：「我找了 N 个助手，分别看 X / Y / Z，稍等。」
String teamCreatedMessage(List<Teammate> members) {
  if (members.isEmpty) return '团队为空';
  final String names = members.map((Teammate m) => m.name).join('、');
  return '我找了 ${members.length} 个助手，分别看 $names，稍等。';
}

/// 进度播报：按成员状态报「X 已完成 / X 还在看 / X 还没开始」。
String progressMessage(AgentTeam team) {
  if (team.members.isEmpty) return '团队为空';
  final List<String> parts = <String>[];
  for (final Teammate m in team.members) {
    switch (m.status) {
      case TeammateStatus.done:
      case TeammateStatus.failed:
      case TeammateStatus.finished:
        parts.add('${m.name} 已完成');
        break;
      case TeammateStatus.working:
        parts.add('${m.name} 还在看');
        break;
      case TeammateStatus.waiting:
        parts.add('${m.name} 在等待');
        break;
      case TeammateStatus.idle:
        parts.add('${m.name} 还没开始');
        break;
    }
  }
  return '${parts.join('，')}。';
}

/// 结果汇总播报：「N 个助手的意见是……需要我详细说说哪个？」
String resultMessage(Map<String, String> replies) {
  if (replies.isEmpty) return '还没有结论。';
  final String summary = replies.entries
      .map((MapEntry<String, String> e) => '${e.key}：${e.value}')
      .join('；');
  return '${replies.length} 个助手的意见是——$summary。需要我详细说说哪个？';
}

/// 成员移除播报：「X 那个已经停了。」
String memberRemovedMessage(String name) => '$name 那个已经停了。';
