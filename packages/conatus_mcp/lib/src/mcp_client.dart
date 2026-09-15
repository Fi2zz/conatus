/// MCP 客户端：握手、工具发现与调用，以及断连收敛。
library;

import 'dart:async';
import 'mcp_client_pending.dart';
import 'mcp_json.dart';
import 'mcp_protocol.dart';
import 'mcp_protocol_content.dart';
import 'mcp_protocol_tool.dart';
import 'mcp_transport.dart';
import 'mcp_types.dart';

/// 一台 MCP server 的会话客户端。
///
/// 请求与响应按自增 int id 关联（见 [McpPendingCalls]），乱序响应也能对上号；
/// 每个请求带 [timeout]，超时以 [McpException]（`timeout`）收场。传输出错或
/// 结束时所有待办以 `disconnected` 失败、[disconnects] 触发一次、[ready] 置假
/// ——上层据此注销该 server 的工具。
///
/// 本包不含遥测依赖：断连只通过 [disconnects] 与 [diagnostics] 两个流表达。
class McpClient {
  /// 构造。[transport] 由调用方提供，其连接生命周期由本客户端驱动。
  McpClient({
    required McpTransport transport,
    required this.serverName,
    this.timeout = const Duration(seconds: 30),
  })  : _transport = transport,
        _pending = McpPendingCalls(serverName: serverName, timeout: timeout);

  /// `tools/list` 的翻页上限；防服务端异常导致死循环。
  static const int _maxPages = 20;

  final McpTransport _transport;
  final McpPendingCalls _pending;
  final StreamController<void> _disconnects =
      StreamController<void>.broadcast();
  StreamSubscription<McpMessage>? _subscription;
  McpServerInfo? _serverInfo;
  int _nextId = 1;
  bool _ready = false;
  bool _closed = false;
  bool _breakReported = false;

  /// server 名：工具名前缀与日志归因都用它。
  final String serverName;

  /// 单次请求超时；`Duration.zero` 表示不限时。
  final Duration timeout;

  /// 握手结果；`initialize` 之前为 `null`。
  McpServerInfo? get serverInfo => _serverInfo;

  /// 握手是否完成且连接仍活着。
  bool get ready => _ready;

  /// 传输层诊断（stderr、坏行、状态变化）。
  Stream<String> get diagnostics => _transport.diagnostics;

  /// 断连信号：传输结束或出错时触发一次（广播流）。
  Stream<void> get disconnects => _disconnects.stream;

  /// 握手：`initialize` 请求 + `notifications/initialized` 通知。
  ///
  /// 服务端回的协议版本与本客户端声明不同也照收，只记录不拒绝。
  Future<McpServerInfo> initialize() async {
    _listen();
    await _transport.connect();
    final McpMessage response = await _request('initialize', <String, Object?>{
      'protocolVersion': kMcpProtocolVersion,
      'capabilities': <String, Object?>{},
      'clientInfo': <String, Object?>{'name': 'conatus', 'version': '0.15.0'},
    });
    final McpServerInfo info = McpServerInfo.fromJson(_resultOf(response));
    _serverInfo = info;
    _ready = true;
    await _transport.send(
      McpMessage.notification(method: 'notifications/initialized'),
    );
    return info;
  }

  /// 列出全部工具：按 `nextCursor` 翻页，直到服务端不再给游标。
  ///
  /// 超过 [_maxPages] 页抛 [McpException]（`too-many-pages`）。
  Future<List<McpTool>> listTools() async {
    final List<McpTool> tools = <McpTool>[];
    String? cursor;
    for (int page = 0; page < _maxPages; page++) {
      final Map<String, Object?> result =
          _resultOf(await _request('tools/list', _cursorParams(cursor)));
      tools.addAll(_toolsOf(result));
      cursor = mcpString(result['nextCursor']);
      if (cursor == null) return tools;
    }
    throw const McpException(
        'too-many-pages', 'tools/list 翻页超过 $_maxPages 页仍未结束');
  }

  /// 调用一个工具；失败结果由 [McpToolResult.failed] 表达，不抛异常。
  Future<McpToolResult> callTool(
    String name,
    Map<String, Object?> arguments,
  ) async {
    final McpMessage response = await _request('tools/call', <String, Object?>{
      'name': name,
      'arguments': arguments,
    });
    return McpToolResult.fromJson(_resultOf(response));
  }

  /// 关闭会话：取消订阅、断开传输、把剩余待办判为失败；幂等。
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _ready = false;
    await _subscription?.cancel();
    _subscription = null;
    _pending.failAll('客户端已关闭', 'closed');
    await _transport.disconnect();
    if (!_disconnects.isClosed) await _disconnects.close();
  }

  void _listen() {
    _subscription ??= _transport.messages.listen(
      _handleMessage,
      onError: _handleError,
      onDone: _handleDone,
    );
  }

  /// 每个请求都先确保订阅已挂上：`initialize` 之外的调用路径也不会漏响应。
  Future<McpMessage> _request(String method, Map<String, Object?>? params) {
    _listen();
    final int id = _nextId++;
    return _pending.register(
      id,
      () => _transport.send(
        McpMessage.request(id: id, method: method, params: params),
      ),
    );
  }

  void _handleMessage(McpMessage message) => _pending.complete(message);

  void _handleError(Object error) => _breakOff('$error');

  void _handleDone() => _breakOff('传输已结束');

  void _breakOff(String cause) {
    if (_breakReported) return;
    _breakReported = true;
    _ready = false;
    _pending.failAll(cause, 'disconnected');
    if (!_disconnects.isClosed) _disconnects.add(null);
  }
}

/// 取出响应的 `result` 对象：失败响应抛 `protocol-error`，形态不对抛
/// `malformed-result`。
Map<String, Object?> _resultOf(McpMessage response) {
  final McpError? error = response.error;
  if (error != null) {
    throw McpException('protocol-error', '${error.code}: ${error.message}');
  }
  final Map<String, Object?>? result = mcpMap(response.result);
  if (result == null) {
    throw const McpException('malformed-result', '响应缺少 result 对象');
  }
  return result;
}

Map<String, Object?>? _cursorParams(String? cursor) =>
    cursor == null ? null : <String, Object?>{'cursor': cursor};

List<McpTool> _toolsOf(Map<String, Object?> result) => <McpTool>[
      for (final Object? item in mcpList(result['tools']))
        if (item is Map<String, Object?>) McpTool.fromJson(item),
    ];
