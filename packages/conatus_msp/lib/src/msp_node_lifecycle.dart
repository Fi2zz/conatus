part of 'msp_node.dart';

Future<void> startMspNode(MspNodeState state) async {
  if (state.running) return;
  state.running = true;
  try {
    state.server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    state.server!.listen((Socket socket) => acceptMspSocket(state, socket));
    final MspEndpoint local = MspEndpoint(
      nodeId: state.nodeId,
      port: state.server!.port,
    );
    state.presence = MspDirectoryPresence(
      nodeId: state.nodeId,
      directory: state.nodesDirectory,
    );
    await state.presence!.announce(local);
    _startDiscovery(state);
    state.heartbeat = Timer.periodic(
      state.timings.heartbeatInterval,
      (_) => pingMspPeers(state),
    );
  } on Object {
    await stopMspNode(state);
    rethrow;
  }
}

void _startDiscovery(MspNodeState state) {
  state.discovery = MspDirectoryDiscovery(
    selfNodeId: state.nodeId,
    directory: state.nodesDirectory,
    intervals: MspDirectoryIntervals(
      pollInterval: state.timings.discoveryPoll,
      staleAfter: state.timings.staleAfter,
    ),
  );
  state.discovery!.watch(
    (MspEndpoint endpoint) => handleMspEndpoint(state, endpoint),
    (String nodeId) => handleMspEndpointRemoved(state, nodeId),
  );
}

Future<void> stopMspNode(MspNodeState state) async {
  if (!state.running && state.server == null) return;
  state.running = false;
  state.heartbeat?.cancel();
  state.heartbeat = null;
  state.discovery?.stop();
  await state.server?.close();
  state.server = null;
  for (final MspConnection connection in state.channels.keys.toList()) {
    await connection.close();
  }
  state.pending.failAll('MSP 节点已停止');
  await state.presence?.withdraw();
  state.presence = null;
  state.endpoints.clear();
}

void handleMspEndpoint(MspNodeState state, MspEndpoint endpoint) {
  state.endpoints[endpoint.nodeId] = endpoint;
  if (!state.running || state.connections.containsKey(endpoint.nodeId)) return;
  if (state.nodeId.compareTo(endpoint.nodeId) < 0) {
    _dialQuietly(state, endpoint);
  }
}

void handleMspEndpointRemoved(MspNodeState state, String nodeId) {
  state.endpoints.remove(nodeId);
  final MspConnection? connection = state.connections[nodeId];
  if (connection != null) unawaited(connection.close());
}

Future<void> _dialQuietly(MspNodeState state, MspEndpoint endpoint) async {
  try {
    await connectMspPeer(state, endpoint.nodeId);
  } on Object {
    // 发现层会在后续扫描中重试；单次拨号失败不影响其他节点。
  }
}

Future<MspConnection> connectMspPeer(MspNodeState state, String peerId) async {
  final MspConnection? existing = state.connections[peerId];
  if (existing != null) return existing;
  final MspEndpoint? endpoint = state.endpoints[peerId];
  if (endpoint == null) throw StateError('未知 MSP 节点：$peerId');
  final Socket socket = await Socket.connect(endpoint.host, endpoint.port);
  final MspPeerChannel channel = _attachConnection(state, socket, true);
  sendMspSignal(channel.connection, _handshake(state, 'hello'));
  await channel.ready.future.timeout(const Duration(seconds: 10));
  return state.connections[peerId]!;
}

void acceptMspSocket(MspNodeState state, Socket socket) {
  _attachConnection(state, socket, false);
}

MspPeerChannel _attachConnection(
  MspNodeState state,
  Socket socket,
  bool outbound,
) {
  late final MspConnection connection;
  connection = MspConnection(
    socket,
    (Uint8List frame) => handleMspFrame(state, connection, frame),
    () => handleMspClosed(state, connection),
  );
  final MspPeerChannel channel = MspPeerChannel(connection, outbound);
  state.channels[connection] = channel;
  return channel;
}

void registerMspPeer(MspNodeState state, MspPeerChannel channel) {
  final String peerId = channel.peerId!;
  final MspConnection? previous = state.connections[peerId];
  state.connections[peerId] = channel.connection;
  if (!channel.ready.isCompleted) channel.ready.complete();
  if (previous != null && !identical(previous, channel.connection)) {
    unawaited(previous.close());
  }
}

void handleMspClosed(MspNodeState state, MspConnection connection) {
  final MspPeerChannel? channel = state.channels.remove(connection);
  final String? peerId = channel?.peerId;
  if (peerId == null) return;
  if (identical(state.connections[peerId], connection)) {
    state.connections.remove(peerId);
    state.pending.failPeer(peerId, 'MSP 连接已关闭');
  }
}

MspSignal _handshake(MspNodeState state, String type) => MspSignal(
      type: type,
      source: state.nodeId,
      options: MspSignalOptions()
        ..payload = <String, Object?>{
          'manifest': state.manifest.toJson(),
        },
    );
