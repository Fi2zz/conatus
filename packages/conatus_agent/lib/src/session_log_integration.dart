/// Session Log 的运行时集成：把业务会话与派生事件写进只追加日志。
///
/// 业务 `Session` 仍是**模型可见的唯一真相源**；[SessionLog] 是它的**超集**：
/// 镜像全部业务事件，再追加 `llm/request` / `llm/response` / `tool/call` 这类
/// 非模型可见的派生事件。因此本集成不会往业务会话里写任何新事件类型，
/// Agent Loop 的既有事件序列保持不变。
library;

import 'dart:async';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'agent_types.dart';

/// 把一次会话（含派生事件）记录进 [SessionLog] 的记录器。
///
/// 日志为每条事件分配自己的 seq；派生事件的 `parentEventId` 指向已记录的最后
/// 一条事件，于是整个会话在日志里是一条因果链。写入串行化，保证链与追加顺序
/// 在多路调用下依然稳定。
class SessionLogRecorder {
  /// 用给定的只追加日志构造。
  SessionLogRecorder({required this.log, this.strictModelVisible = false});

  /// 目标日志。
  final SessionLog log;

  /// 是否在每次 `llm/request` 落盘后、**发送前**校验「模型可见即已记录」。
  ///
  /// 开发模式建议开启（违反不变式会抛 [StateError]）；生产保持关闭——每次校验都要
  /// 回读一遍会话日志，O(n) 一次请求。校验逻辑见 `model_visible_invariant.dart`。
  final bool strictModelVisible;

  String? _sessionId;
  String? _lastEventId;
  Disposer? _detach;
  Future<void> _pending = Future<void>.value();

  /// 正在镜像的会话 id；未 [attach] 时为 `null`。
  String? get sessionId => _sessionId;

  /// 已记录的最后一条事件 id（派生事件的 `parentEventId`）。
  String? get lastEventId => _lastEventId;

  /// 开始镜像 [session]：先补记已有事件，再订阅后续追加。
  ///
  /// 返回撤销函数（幂等）；重复调用会先撤销上一次订阅。
  Disposer attach(Session session) {
    detach();
    _sessionId = session.id;
    session.replay((SessionEvent event) => unawaited(_mirror(event)));
    final Disposer off =
        session.onEvent((SessionEvent event) => unawaited(_mirror(event)));
    _detach = off;
    return () {
      off();
      if (identical(_detach, off)) _detach = null;
    };
  }

  /// 停止镜像当前会话。
  void detach() {
    _detach?.call();
    _detach = null;
  }

  /// 记一条派生事件（非模型可见）；尚未 [attach] 时静默忽略。
  Future<void> record(String type, {Object? data}) {
    final String? sessionId = _sessionId;
    if (sessionId == null) return Future<void>.value();
    return _serialize(() async {
      final SessionEvent recorded = await log.append(
        SessionEvent.create(
          sessionId: sessionId,
          type: type,
          seq: 0,
          data: data,
          parentEventId: _lastEventId,
        ),
      );
      _lastEventId = recorded.id;
    });
  }

  Future<void> _mirror(SessionEvent event) => _serialize(() async {
        // 业务事件自带 parentEventId 时保留（业务因果），否则接到日志链尾。
        final SessionEvent recorded = await log.append(
          event.copyWith(parentEventId: event.parentEventId ?? _lastEventId),
        );
        _lastEventId = recorded.id;
      });

  /// 串行化日志写入。
  Future<void> _serialize(Future<void> Function() task) {
    final Future<void> result = _pending.then((_) => task());
    _pending = result.then((_) {}, onError: (Object _) {});
    return result;
  }
}

/// 记录每一次工具调用（`tool/call`），`group` 用于 MCP 等来源归因。
///
/// 工具**结果**不重复记录：业务会话的 `tool/result` 事件已被镜像。
Disposer instrumentSessionLogTools(
  ToolRegistry tools,
  SessionLogRecorder recorder,
) =>
    tools.use((ToolCall call, Future<ToolResult> Function() next) async {
      await recorder.record(kToolCallEvent, data: <String, Object?>{
        'name': call.name,
        'callId': call.callId,
        'group': tools.groupOf(call.name),
        'args': call.arguments,
      });
      return next();
    });

/// `ctx.sessionLogRecorder`：当前上下文可见的 [SessionLogRecorder]。
extension SessionLogRecorderContext on Context {
  /// 取当前上下文可见的 [SessionLogRecorder]（未提供时抛 [StateError]）。
  SessionLogRecorder get sessionLogRecorder =>
      require<SessionLogRecorder>('sessionLogRecorder');
}

/// 将 [SessionLogRecorder] 作为 `'sessionLogRecorder'` 服务提供到上下文。
///
/// 依赖 `sessionLog` 服务，缺少时自动补一个（见 `provideSessionLog`）。提供之后
/// `provideAgentLoop` 会接管镜像、模型调用与工具调用的记录。
SessionLogRecorder provideSessionLogRecorder(
  Context ctx, {
  SessionLogRecorder? recorder,
  bool strictModelVisible = false,
}) {
  final SessionLogRecorder resolved = recorder ??
      SessionLogRecorder(
        log: ctx.get<SessionLog>('sessionLog') ?? provideSessionLog(ctx),
        strictModelVisible: strictModelVisible,
      );
  ctx.provide('sessionLogRecorder', resolved);
  return resolved;
}
