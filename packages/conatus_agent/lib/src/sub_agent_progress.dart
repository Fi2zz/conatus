/// 子 Agent 的进度事件与工具代理。
///
/// 子 Agent 跑在自己的 [Session] 上，那个会话不参与屏上记录——所以它的每一步
/// 对用户是黑箱：界面静止几十秒，结束后只吐一段结论字符串。看不见就不敢用，
/// 所以这里把「起了什么、每轮调了什么、成没成」逐条报给宿主。
library;

import 'package:conatus_foundation/conatus_foundation.dart';

/// 子 Agent 的一次进度事件。
sealed class SubAgentEvent {
  const SubAgentEvent();

  /// 事件类型名（调试 / 断言用）。
  String get kind;
}

/// 委托开始。
class SubAgentStarted extends SubAgentEvent {
  const SubAgentStarted(this.task);

  /// 交办的子任务描述。
  final String task;

  @override
  String get kind => 'started';
}

/// 子 Agent 要调一个工具。
class SubAgentToolCall extends SubAgentEvent {
  const SubAgentToolCall(this.tool);

  /// 工具名。
  final String tool;

  @override
  String get kind => 'tool-call';
}

/// 工具返回了。
class SubAgentToolDone extends SubAgentEvent {
  const SubAgentToolDone(this.tool, this.failed);

  /// 工具名。
  final String tool;

  /// 是否失败。
  final bool failed;

  @override
  String get kind => 'tool-done';
}

/// 一轮跑完。
class SubAgentRound extends SubAgentEvent {
  const SubAgentRound(this.step, this.reply);

  /// 第几步（1 起）。
  final int step;

  /// 本轮模型的正文（已截断）。
  final String reply;

  @override
  String get kind => 'round';
}

/// 委托收口。
class SubAgentFinished extends SubAgentEvent {
  const SubAgentFinished(this.status, this.rounds, this.tools);

  /// `success` / `failed`。
  final String status;

  /// 跑了几轮。
  final int rounds;

  /// 用过的工具（去重后按序）。
  final List<String> tools;

  @override
  String get kind => 'finished';
}

/// 进度回调。
typedef SubAgentProgressReporter = void Function(SubAgentEvent event);

/// 转发调用并顺带报进度的工具代理。
///
/// 不用「跑完一轮再看子会话事件」的办法：那拿不到**开始**的时机（界面在
/// `await` 期间是完全静止的），也让宿主绑定到子会话的内部结构上。包一层
/// 工具则与主链路的中间件同构，且调用与返回两端都能拿到。
class ProgressTool extends Tool {
  ProgressTool(this.inner, this.reporter);

  /// 被代理的工具。
  final Tool inner;
  final SubAgentProgressReporter reporter;

  @override
  String get name => inner.name;

  @override
  String get description => inner.description;

  @override
  ToolRisk get riskLevel => inner.riskLevel;

  @override
  List<ParamSpec> get params => inner.params;

  @override
  Future<ToolResult> call(ToolContext ctx) async {
    reporter(SubAgentToolCall(name));
    final ToolResult result = await inner.call(ctx);
    reporter(SubAgentToolDone(name, result.isError));
    return result;
  }
}

/// 按 [allowed] 从主注册表取出工具并逐个包上进度代理。
///
/// 子注册表**复制主注册表的守卫与中间件**（`copyPipelineTo`）：审批、工具结果
/// 驱逐、hooks、lint 等必须对子 Agent 的工具调用同样生效。此前子表是全新的空
/// 管线——既不驱逐大结果（`read_file` 20 万字符直接灌进子历史），也让显式点名的
/// high 工具绕过人工确认。工具本身仍只有白名单内的那些。
ToolRegistry buildChildRegistry(
  ToolRegistry source,
  Set<String> allowed, {
  SubAgentProgressReporter? reporter,
  Set<String> excludeTags = const <String>{},
}) {
  final ToolRegistry child = ToolRegistry(defaultTimeout: source.defaultTimeout);
  source.copyPipelineTo(child, excludeTags: excludeTags);
  for (final String name in allowed) {
    final Tool? tool = source.get(name);
    if (tool == null) continue;
    child.register(
      reporter == null ? tool : ProgressTool(tool, reporter),
    );
  }
  return child;
}
