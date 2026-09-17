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
import 'package:conatus_foundation/conatus_foundation.dart';
import 'teammate.dart';

/// 一次成员轮次的结局。
class TeamTurn {
  const TeamTurn({required this.completed, required this.reply});

  /// 是否正常收口（未被取消、未失败）。
  final bool completed;

  /// 模型最终回复（被取消时为空串）。
  final String reply;
}

/// 成员状态变更回调：runtime 在 idle / working / failed 之间切换时调用。
typedef TeammateMutation = void Function(TeammateStatus next);

/// 一个成员的运行时：持有独立 [Session] 与 [AgentLoop]，串行处理消息队列。
class MemberRuntime {
  MemberRuntime({
    required this.id,
    required this.session,
    required this.loop,
    required this.onStatus,
  });

  /// 成员 ID（与 [Teammate.id] 对齐）。
  final String id;

  /// 独立会话；保留本成员的全部历史，不污染队长上下文。
  final Session session;

  /// 独立 Agent Loop；成员的模型调用与工具执行入口。
  final AgentLoop loop;

  /// 状态变更回调。
  final TeammateMutation onStatus;

  final List<_Pending> _pending = <_Pending>[];
  AgentCancel? _cancel;
  bool _running = false;

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

  /// 释放底层资源：取消在途、关 Session。幂等。
  void dispose() {
    _cancel?.cancel();
    session.close();
  }

  Future<void> _pump() async {
    if (_running) return;
    _running = true;
    try {
      while (_pending.isNotEmpty) {
        final _Pending p = _pending.first;
        _cancel = AgentCancel();
        onStatus(TeammateStatus.working);
        try {
          final AgentTurn turn = await loop.run(p.message, cancel: _cancel);
          onStatus(TeammateStatus.idle);
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
