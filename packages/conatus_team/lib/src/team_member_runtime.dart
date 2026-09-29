/// 成员运行时：独立 Session + AgentLoop + 当前轮取消信号。
///
/// [AgentTeam.send] / [wait] / [interrupt] 的实际执行者。send 追加用户消息
/// 到独立 [Session]，启动一轮 [AgentLoop.run]；wait 等所有 pending 轮结束；
/// interrupt 通过 [AgentCancel.cancel] 竞速取消在途轮次。轮次串行（同一成员
/// 不会并发调模型），队列保证消息按序处理——与 sub-agent 的隔离委托一致，
/// 但成员持久存活，可多次收发。
library;

import 'dart:async';

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'team_activity.dart';
import 'teammate.dart';

/// 一次成员轮次的结局。
class TeamTurn {
  const TeamTurn({required this.completed, required this.reply});

  /// 是否正常收口（未被取消、未失败）。
  final bool completed;

  /// 模型最终回复（被取消时为空串）。
  final String reply;
}

/// 成员状态变更回调：runtime 在 idle / working / finished / failed 之间
/// 切换时调用。
typedef TeammateMutation = void Function(TeammateStatus next);

/// 活动回调：成员每产出一段内容 / 调一次工具时调用。
typedef TeammateActivitySink = void Function(TeammateActivity activity);

/// 用 [onStream] 构造成员的 [AgentLoop]。
///
/// 工厂而非直接注入，是为了让 runtime 掌控 `onStream` 的接线——成员的活动从
/// 这里出，不能由外部随手关掉。
typedef MemberLoopFactory = AgentLoop Function(
  void Function(LlmStreamEvent event) onStream,
);

/// 一个成员的运行时：持有独立 [Session] 与 [AgentLoop]，串行处理消息队列。
class MemberRuntime {
  MemberRuntime({
    required this.id,
    required this.session,
    required MemberLoopFactory loopFactory,
    required this.onStatus,
    this.onActivity,
  }) {
    // 接线必须在构造体里做：字段初始化器读不到实例成员，而 `onStream` 要
    // 指向本成员自己的处理器。AgentLoop 的 onStream 是 final，只能这样接。
    loop = loopFactory(_emitStream);
    _watchSession();
  }

  /// 成员 ID（与 [Teammate.id] 对齐）。
  final String id;

  /// 独立会话；保留本成员的全部历史，不污染队长上下文。
  final Session session;

  /// 独立 Agent Loop；成员的模型调用与工具执行入口。
  ///
  /// 晚初始化：构造体里用 [_emitStream] 接上 `onStream` 后才可用。
  late final AgentLoop loop;

  /// 状态变更回调。
  final TeammateMutation onStatus;

  /// 活动回调；缺省不产生（成员对界面仍是黑箱）。
  final TeammateActivitySink? onActivity;

  final List<_Pending> _pending = <_Pending>[];
  int _round = 0;
  AgentCancel? _cancel;
  bool _running = false;
  Disposer? _sessionWatch;

  /// 挂上会话事件流，捕捉工具调用与结果。
  ///
  /// 正文走 [AgentLoop] 的 `onStream`，而工具调用只在 `assistant` 事件里、
  /// 结果只在 `tool/result` 事件里——两条来源都要接才拼得出完整轨迹。
  void _watchSession() {
    _sessionWatch = session.onEvent((SessionEvent event) {
      if (event.type == kAssistantMessageEvent) {
        _emitToolCalls(event);
      } else if (event.type == kToolResultEvent) {
        _emitToolResult(event);
      }
    });
  }

  void _emitToolCalls(SessionEvent event) {
    final Object? calls = _field(event, 'toolCalls');
    if (calls is! List) return;
    for (final Object? call in calls) {
      final Object? name = call is Map ? call['name'] : null;
      if (name is String) onActivity?.call(TeammateToolCall(name));
    }
  }

  void _emitToolResult(SessionEvent event) {
    final Object? name = _field(event, 'name');
    if (name is! String || name.isEmpty) return;
    onActivity?.call(TeammateToolResult(
      name,
      failed: _field(event, 'isError') == true,
      preview: _firstLine('${_field(event, 'content') ?? ''}'),
    ));
  }

  /// LLM 流事件 → 活动。正文与思考各自成段。
  void _emitStream(LlmStreamEvent event) {
    if (event is LlmTextDelta) {
      onActivity?.call(TeammateText(event.text));
    } else if (event is LlmReasoningDelta) {
      onActivity?.call(TeammateReasoning(event.text));
    }
  }

  static Object? _field(SessionEvent event, String key) {
    final Object? data = event.data;
    return data is Map ? data[key] : null;
  }

  static String _firstLine(String text) {
    final String line = text.trim().split('\n').first;
    return line.length <= 60 ? line : '${line.substring(0, 60)}…';
  }

  /// 追加一条用户消息，排队等本成员跑一轮；返回本轮结局。
  Future<TeamTurn> send(String message) {
    final Completer<TeamTurn> completer = Completer<TeamTurn>();
    _pending.add(_Pending(message, completer));
    _pump();
    return completer.future;
  }

  /// 等所有 pending 轮次结束；空队列立即返回。超时不抛错，直接返回。
  Future<void> wait({Duration? timeout}) async {
    final List<Future<TeamTurn>> futures = <Future<TeamTurn>>[
      for (final _Pending p in List<_Pending>.of(_pending)) p.completer.future,
    ];
    if (futures.isEmpty) return;
    final Future<void> all = Future.wait(futures).then<void>((_) {});
    if (timeout == null) {
      await all;
    } else {
      await all.timeout(timeout, onTimeout: () {});
    }
  }

  /// 中断在途轮次（竞速停止等待）；后续 pending 轮继续跑。
  Future<void> interrupt() async {
    _cancel?.cancel();
  }

  /// 释放底层资源：取消在途、摘掉会话订阅、关 Session。幂等。
  void dispose() {
    _cancel?.cancel();
    _sessionWatch?.call();
    _sessionWatch = null;
    session.close();
  }

  Future<void> _pump() async {
    if (_running) return;
    _running = true;
    try {
      while (_pending.isNotEmpty) {
        final _Pending p = _pending.first;
        _cancel = AgentCancel();
        _round++;
        onStatus(TeammateStatus.working);
        onActivity?.call(TeammateRoundStart(_round));
        try {
          final AgentTurn turn = await loop.run(p.message, cancel: _cancel);
          onStatus(TeammateStatus.finished);
          p.completer.complete(TeamTurn(completed: true, reply: turn.reply));
        } on AgentCancelled {
          onStatus(TeammateStatus.idle);
          p.completer.complete(const TeamTurn(completed: false, reply: ''));
        } catch (error) {
          onStatus(TeammateStatus.failed);
          p.completer.completeError(error);
        } finally {
          _cancel = null;
          _pending.remove(p);
        }
      }
    } finally {
      _running = false;
    }
  }
}

class _Pending {
  const _Pending(this.message, this.completer);
  final String message;
  final Completer<TeamTurn> completer;
}
