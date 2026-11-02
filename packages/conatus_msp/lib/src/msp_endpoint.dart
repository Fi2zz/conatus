class MspEndpoint {
  const MspEndpoint({
    required this.nodeId,
    required this.port,
    this.host = '127.0.0.1',
  });

  static MspEndpoint? fromDeclaration(Object? raw, String selfNodeId) {
    if (raw is! Map) return null;
    final Object? nodeId = raw['node_id'];
    if (nodeId is! String || nodeId.isEmpty || nodeId == selfNodeId) {
      return null;
    }
    return _fromEndpoint(nodeId, raw['endpoint']);
  }

  final String nodeId;
  final String host;
  final int port;

  Map<String, Object?> toDeclaration(double timestamp) => <String, Object?>{
        'node_id': nodeId,
        'endpoint': <String, Object?>{
          'transport_type': 'tcp',
          'address': <String, Object?>{'host': host, 'port': port},
        },
        'timestamp': timestamp,
      };
}

MspEndpoint? _fromEndpoint(String nodeId, Object? raw) {
  if (raw is! Map) return null;
  final Object? address = raw['address'];
  if (raw['transport_type'] != 'tcp' || address is! Map) return null;
  final Object? host = address['host'];
  final Object? port = address['port'];
  if (host is! String || port is! int) return null;
  return MspEndpoint(nodeId: nodeId, host: host, port: port);
}
