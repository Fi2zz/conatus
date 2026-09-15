/// stdio 传输：MCP server 是子进程，stdin / stdout 走逐行 JSON-RPC。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'mcp_json.dart';
import 'mcp_protocol.dart';
import 'mcp_transport.dart';
import 'mcp_types.dart';

/// 以子进程管道为通道的传输。
///
/// stdout 逐行解析 JSON-RPC；解析不了的那一行只写 [diagnostics]，不会杀死
/// 连接。stderr 也全量进 [diagnostics]。子进程退出或管道中断时，[messages]
/// 收到一个 [McpException]（`server-exited`）并随即关闭——上层的等待因此不会
/// 永久挂起。
class StdioTransport implements McpTransport {
  /// 构造。命令、参数、环境与工作目录之外不加旋钮，避免参数溢出。
  StdioTransport({
    required String command,
    List<String> args = const <String>[],
    Map<String, String> env = const <String, String>{},
    String? workingDirectory,
  })  : _command = command,
        _args = args,
        _env = env,
        _workingDirectory = workingDirectory;

  final String _command;
  final List<String> _args;
  final Map<String, String> _env;
  final String? _workingDirectory;
  final StreamController<McpMessage> _messages = StreamController<McpMessage>();
  final StreamController<String> _diagnostics =
      StreamController<String>.broadcast();
  final List<StreamSubscription<String>> _subscriptions =
      <StreamSubscription<String>>[];
  Process? _process;
  bool _closed = true;

  /// 连接是否已建立。
  bool get connected => !_closed;

  @override
  Stream<McpMessage> get messages => _messages.stream;

  @override
  Stream<String> get diagnostics => _diagnostics.stream;

  @override
  Future<void> connect() async {
    if (!_closed) return;
    final Process process = await Process.start(
      _command,
      _args,
      environment: <String, String>{...Platform.environment, ..._env},
      workingDirectory: _workingDirectory,
    );
    _process = process;
    _closed = false;
    _listen(process.stdout, _handleLine, 'stdout');
    _listen(process.stderr, _diagnose, 'stderr');
    unawaited(process.exitCode.then(_handleExit));
  }

  @override
  Future<void> send(McpMessage message) async {
    final Process? process = _process;
    if (process == null) {
      throw const McpException('not-connected', 'stdio 传输尚未连接');
    }
    process.stdin.writeln(jsonEncode(message.toJson()));
    await process.stdin.flush();
  }

  @override
  Future<void> disconnect() async {
    if (_closed) return;
    _closed = true;
    for (final StreamSubscription<String> sub
        in List<StreamSubscription<String>>.of(_subscriptions)) {
      await sub.cancel();
    }
    _subscriptions.clear();
    _process?.kill();
    _process = null;
    await _closeSinks();
  }

  void _listen(
    Stream<List<int>> stream,
    void Function(String) onLine,
    String label,
  ) {
    _subscriptions.add(
      stream.transform(utf8.decoder).transform(const LineSplitter()).listen(
            onLine,
            onError: (Object error) => _diagnose('$label: $error'),
          ),
    );
  }

  void _handleLine(String line) {
    final Object? decoded = mcpDecode(line);
    if (decoded is! Map<String, Object?>) {
      _diagnose('无法解析的 stdout 行：$line');
      return;
    }
    _emit(McpMessage.fromJson(decoded));
  }

  void _handleExit(int code) {
    if (_closed) return;
    _closed = true;
    _report(McpException('server-exited', 'MCP server 进程已退出（exit $code）'));
  }

  void _report(Object error) {
    if (_messages.isClosed) return;
    _messages.addError(error);
    unawaited(_closeSinks());
  }

  void _emit(McpMessage message) {
    if (_messages.isClosed) return;
    _messages.add(message);
  }

  void _diagnose(String text) {
    if (_diagnostics.isClosed) return;
    _diagnostics.add(text);
  }

  /// 关闭消息与诊断流；幂等。
  ///
  /// **不 await** `messages` 的 `done`：单订阅流在没人监听时永远收不到 done
  /// 事件，等它会让 [disconnect] 永久挂起。
  Future<void> _closeSinks() async {
    unawaited(_messages.close());
    unawaited(_diagnostics.close());
  }
}
