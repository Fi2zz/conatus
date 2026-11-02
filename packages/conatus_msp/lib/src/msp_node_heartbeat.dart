part of 'msp_node.dart';

void pingMspPeers(MspNodeState state) {
  if (!state.running) return;
  final Duration timeout = state.timings.heartbeatInterval * 3;
  for (final MapEntry<String, MspConnection> entry
      in state.connections.entries.toList()) {
    final DateTime? seen = state.lastSeen[entry.key];
    if (seen != null && DateTime.now().difference(seen) > timeout) {
      unawaited(entry.value.close());
      continue;
    }
    final MspSignal ping = MspSignal(
      type: 'ping',
      source: state.nodeId,
      options: MspSignalOptions(target: entry.key),
    );
    _sendBestEffort(entry.value, ping);
  }
}
