part of 'msp_node.dart';

Future<MspToolResult> callMspTool(
  MspNodeState state,
  String peerId,
  String tool,
  Map<String, Object?> args,
) async {
  final MspConnection connection;
  try {
    connection = await _ensureConnection(state, peerId);
  } on Object catch (error) {
    return MspToolResult.failure('$error');
  }
  final MspPendingRequest request = state.pending.create(peerId);
  final MspSignalOptions options = MspSignalOptions(
    target: peerId,
    reqid: request.id,
  )..payload = <String, Object?>{'tool': tool, 'args': args};
  try {
    sendMspSignal(
      connection,
      MspSignal(type: 'tool_call', source: state.nodeId, options: options),
    );
  } on Object catch (error) {
    state.pending.remove(request.id);
    await connection.close();
    return MspToolResult.failure('$error');
  }
  try {
    return await request.completer.future.timeout(state.timings.callTimeout);
  } on TimeoutException {
    state.pending.remove(request.id);
    return MspToolResult.failure('调用 $tool 超时');
  }
}

Future<MspConnection> _ensureConnection(MspNodeState state, String peerId) {
  final MspConnection? existing = state.connections[peerId];
  if (existing != null) return Future<MspConnection>.value(existing);
  return connectMspPeer(state, peerId);
}
