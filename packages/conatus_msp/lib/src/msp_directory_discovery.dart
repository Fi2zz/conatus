import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'msp_endpoint.dart';

class MspDirectoryIntervals {
  const MspDirectoryIntervals({
    this.pollInterval = const Duration(seconds: 30),
    this.staleAfter = const Duration(seconds: 30),
  });

  final Duration pollInterval;
  final Duration staleAfter;
}

typedef MspEndpointAdded = void Function(MspEndpoint endpoint);
typedef MspEndpointRemoved = void Function(String nodeId);

class MspDirectoryDiscovery {
  MspDirectoryDiscovery({
    required this.selfNodeId,
    required this.directory,
    this.intervals = const MspDirectoryIntervals(),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    directory.createSync(recursive: true);
  }

  final String selfNodeId;
  final Directory directory;
  final MspDirectoryIntervals intervals;
  final DateTime Function() _clock;
  final Map<String, String> _known = <String, String>{};
  MspEndpointAdded? _onAdd;
  MspEndpointRemoved? _onRemove;
  Timer? _timer;
  bool _stopped = false;

  void watch(MspEndpointAdded onAdd, MspEndpointRemoved onRemove) {
    _onAdd = onAdd;
    _onRemove = onRemove;
    _stopped = false;
    scan();
    _timer?.cancel();
    _timer = Timer.periodic(intervals.pollInterval, (_) => scan());
  }

  List<MspEndpoint> scan() {
    final _MspScanResult result = _readCurrent();
    _emitChanges(result);
    _known
      ..clear()
      ..addAll(result.fingerprints);
    return result.endpoints.values.toList(growable: false);
  }

  void stop() {
    _stopped = true;
    _timer?.cancel();
    _timer = null;
  }

  _MspScanResult _readCurrent() {
    final Map<String, MspEndpoint> endpoints = <String, MspEndpoint>{};
    final Map<String, String> fingerprints = <String, String>{};
    for (final File file in directory.listSync().whereType<File>()) {
      if (!file.path.endsWith('.json')) continue;
      final Map<String, Object?>? declaration = _readDeclaration(file);
      final MspEndpoint? endpoint = MspEndpoint.fromDeclaration(
        declaration,
        selfNodeId,
      );
      if (endpoint == null || _expired(declaration!)) continue;
      endpoints[endpoint.nodeId] = endpoint;
      fingerprints[endpoint.nodeId] = jsonEncode(declaration);
    }
    return _MspScanResult(endpoints, fingerprints);
  }

  Map<String, Object?>? _readDeclaration(File file) {
    try {
      final Object? decoded = jsonDecode(file.readAsStringSync());
      if (decoded is Map) return Map<String, Object?>.from(decoded);
    } on Object {
      return null;
    }
    return null;
  }

  bool _expired(Map<String, Object?> declaration) {
    final Object? raw = declaration['timestamp'];
    if (raw is! num) return false;
    final double elapsed = _clock().microsecondsSinceEpoch / 1000000 - raw;
    return elapsed > intervals.staleAfter.inMicroseconds / 1000000;
  }

  void _emitChanges(_MspScanResult result) {
    if (_stopped) return;
    for (final MspEndpoint endpoint in result.endpoints.values) {
      if (_known[endpoint.nodeId] != result.fingerprints[endpoint.nodeId]) {
        _onAdd?.call(endpoint);
      }
    }
    for (final String nodeId in _known.keys) {
      if (!result.endpoints.containsKey(nodeId)) _onRemove?.call(nodeId);
    }
  }
}

class _MspScanResult {
  const _MspScanResult(this.endpoints, this.fingerprints);

  final Map<String, MspEndpoint> endpoints;
  final Map<String, String> fingerprints;
}
