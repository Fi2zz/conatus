/// 待办请求表：id 关联、超时与失败收敛（内部实现，不对外导出）。
library;

import 'dart:async';
import 'mcp_protocol.dart';
import 'mcp_types.dart';

/// [McpClient] 的待办请求簿。
///
/// 每个请求按自增 id 入账并附一个超时计时器；响应到达即出账并完成对应的
/// future。断连或关闭时 [failAll] 把所有在账请求一次性判失败，等待方不会
/// 永久悬挂。
class McpPendingCalls {
  /// 构造；[serverName] 与 [timeout] 只用于错误文案与计时。
  McpPendingCalls({required this.serverName, required this.timeout});

  /// 所属 server 名（错误文案用）。
  final String serverName;

  /// 单次请求超时；`Duration.zero` 表示不限时。
  final Duration timeout;

  final Map<int, Completer<McpMessage>> _pending =
      <int, Completer<McpMessage>>{};

  /// 在账请求数。
  int get length => _pending.length;

  /// 登记请求 [id]，由 [send] 负责真正发出（其异常收敛到本次请求上）。
  Future<McpMessage> register(int id, Future<void> Function() send) {
    final Completer<McpMessage> completer = Completer<McpMessage>();
    _pending[id] = completer;
    final Timer? timer = _armTimeout(id);
    unawaited(_guardedSend(id, send));
    return completer.future.whenComplete(() => timer?.cancel());
  }

  /// 按 id 关联一条响应；无关消息（通知、服务端主动请求）忽略。
  void complete(McpMessage message) {
    final Object? id = message.id;
    if (id is! int) return;
    final Completer<McpMessage>? completer = _pending.remove(id);
    if (completer == null) return;
    if (!completer.isCompleted) completer.complete(message);
  }

  /// 把 [id] 的在账请求判为失败；不在账（已超时或已完成）时无动作。
  void fail(int id, Object error) {
    final Completer<McpMessage>? completer = _pending.remove(id);
    if (completer == null) return;
    if (!completer.isCompleted) completer.completeError(error);
  }

  /// 把所有在账请求判为失败，[cause] 写进消息、[code] 作为错误码。
  void failAll(String cause, String code) {
    final McpException error = McpException(
      code,
      '与服务端 "$serverName" 的连接中断：$cause',
    );
    for (final int id in _pending.keys.toList(growable: false)) {
      fail(id, error);
    }
  }

  Future<void> _guardedSend(int id, Future<void> Function() send) async {
    try {
      await send();
    } catch (error) {
      fail(id, error);
    }
  }

  Timer? _armTimeout(int id) {
    if (timeout <= Duration.zero) return null;
    return Timer(
      timeout,
      () => fail(
        id,
        McpException('timeout', '请求 $id 在 ${timeout.inMilliseconds}ms 内没有响应'),
      ),
    );
  }
}
