part of 'msp_node.dart';

void handleMspFrame(
  MspNodeState state,
  MspConnection connection,
  Uint8List frame,
) {
  final MspPeerChannel? channel = state.channels[connection];
  if (channel == null) return;
  try {
    final MspSignal signal = decodeMspSignal(frame);
    if (channel.peerId == null) {
      _handleHandshake(state, channel, signal);
      return;
    }
    state.lastSeen[channel.peerId!] = DateTime.now();
    _dispatchSignal(state, channel, signal);
  } on FormatException catch (error) {
    _sendProtocolError(connection, state.nodeId, null, '$error');
  }
}

void _handleHandshake(
  MspNodeState state,
  MspPeerChannel channel,
  MspSignal signal,
) {
  final String expected = channel.outbound ? 'ack' : 'hello';
  if (signal.type != expected) {
    unawaited(channel.connection.close());
    return;
  }
  final MspManifest? manifest = _peerManifest(signal);
  if (manifest == null) {
    unawaited(channel.connection.close());
    return;
  }
  channel.peerId = signal.source;
  state.peerManifests[signal.source] = manifest;
  if (!channel.outbound) {
    sendMspSignal(channel.connection, _handshake(state, 'ack'));
  }
  registerMspPeer(state, channel);
}

MspManifest? _peerManifest(MspSignal signal) {
  try {
    final Object? raw = signal.payload['manifest'];
    if (raw is! Map) return null;
    return MspManifest.fromJson(Map<String, Object?>.from(raw));
  } on Object {
    return null;
  }
}

void _dispatchSignal(
  MspNodeState state,
  MspPeerChannel channel,
  MspSignal signal,
) {
  if (signal.type == 'tool_result') {
    state.pending.complete(signal);
    return;
  }
  if (signal.type == 'tool_call') {
    unawaited(_runTool(state, channel, signal));
    return;
  }
  if (signal.type == 'signal') {
    state.handlers.dispatch(signal);
    return;
  }
  _dispatchControl(state, channel, signal);
}

void _dispatchControl(
  MspNodeState state,
  MspPeerChannel channel,
  MspSignal signal,
) {
  if (signal.type == 'ping') {
    sendMspSignal(channel.connection, _replySignal(state, signal, 'pong'));
    return;
  }
  if (signal.type == 'pong' || signal.type == 'manifest_update') return;
  if (signal.type == 'error') {
    stderr.writeln('[msp] 对端 ${channel.peerId} 返回错误：${signal.payload}');
    return;
  }
  _sendProtocolError(channel.connection, state.nodeId, signal, '未知消息类型');
}

Future<void> _runTool(
  MspNodeState state,
  MspPeerChannel channel,
  MspSignal signal,
) async {
  final String? reqid = signal.reqid;
  if (reqid == null || reqid.isEmpty) return;
  final String tool = '${signal.payload['tool'] ?? ''}';
  final Object? rawArgs = signal.payload['args'];
  final Map<String, Object?> args =
      rawArgs is Map ? Map<String, Object?>.from(rawArgs) : <String, Object?>{};
  MspToolResult result;
  try {
    final MspToolHandler? handler = state.tools[tool];
    if (handler == null) throw StateError('未知工具：$tool');
    result = MspToolResult.fromValue(await handler(args));
  } on Object catch (error) {
    result = MspToolResult.failure('$error');
  }
  final MspSignal reply = _replySignal(state, signal, 'tool_result');
  reply.options.payload = result.toPayload();
  _sendBestEffort(channel.connection, reply);
}

Future<void> publishMspSignal(
  MspNodeState state,
  String path,
  Map<String, Object?> payload,
) async {
  final MspSignalOptions options = MspSignalOptions(path: path)
    ..payload = payload;
  final MspSignal signal = MspSignal(
    type: 'signal',
    source: state.nodeId,
    options: options,
  );
  for (final MspConnection connection in state.connections.values.toList()) {
    _sendBestEffort(connection, signal);
  }
}

void _sendBestEffort(MspConnection connection, MspSignal signal) {
  try {
    sendMspSignal(connection, signal);
  } on Object {
    unawaited(connection.close());
  }
}

MspSignal _replySignal(MspNodeState state, MspSignal request, String type) =>
    MspSignal(
      type: type,
      source: state.nodeId,
      options: MspSignalOptions(target: request.source, reqid: request.reqid),
    );

void _sendProtocolError(
  MspConnection connection,
  String source,
  MspSignal? request,
  String message,
) {
  final MspSignalOptions options = MspSignalOptions(
    target: request?.source,
    reqid: request?.reqid,
  )..payload = <String, Object?>{'code': -32600, 'message': message};
  _sendBestEffort(
    connection,
    MspSignal(type: 'error', source: source, options: options),
  );
}
