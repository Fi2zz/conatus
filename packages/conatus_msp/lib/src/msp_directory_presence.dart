import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'msp_endpoint.dart';

class MspDirectoryPresenceConfig {
  const MspDirectoryPresenceConfig({
    this.renewInterval = const Duration(seconds: 10),
    this.clock,
    this.beforeWrite,
  });

  final Duration renewInterval;
  final DateTime Function()? clock;
  final Future<void> Function()? beforeWrite;
}

class MspDirectoryPresence {
  MspDirectoryPresence({
    required this.nodeId,
    required this.directory,
    this.config = const MspDirectoryPresenceConfig(),
  });

  final String nodeId;
  final Directory directory;
  final MspDirectoryPresenceConfig config;
  Timer? _renewTimer;
  Future<void> _writes = Future<void>.value();
  int _generation = 0;
  bool _active = false;

  Future<void> announce(MspEndpoint endpoint) async {
    final int generation = ++_generation;
    _active = true;
    _renewTimer?.cancel();
    await _queueWrite(endpoint, generation);
    if (_active && generation == _generation) {
      _renewTimer =
          Timer.periodic(config.renewInterval, (_) => _renew(endpoint));
    }
  }

  Future<void> withdraw() async {
    _generation++;
    _active = false;
    _renewTimer?.cancel();
    _renewTimer = null;
    await _writes;
    await _deleteDeclaration();
  }

  File get _declarationFile => File('${directory.path}/$nodeId.json');

  Future<void> _queueWrite(MspEndpoint endpoint, int generation) {
    final Future<void> operation = _writes.then((_) async {
      if (!_active || generation != _generation) return;
      await config.beforeWrite?.call();
      if (!_active || generation != _generation) return;
      await _write(endpoint);
    });
    _writes = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> _write(MspEndpoint endpoint) async {
    directory.createSync(recursive: true);
    final DateTime now = (config.clock ?? DateTime.now)();
    final double timestamp = now.microsecondsSinceEpoch / 1000000;
    final File temporary = File('${_declarationFile.path}.tmp');
    await temporary
        .writeAsString(jsonEncode(endpoint.toDeclaration(timestamp)));
    await temporary.rename(_declarationFile.path);
  }

  Future<void> _deleteDeclaration() async {
    try {
      await _declarationFile.delete();
    } on FileSystemException {
      if (_declarationFile.existsSync()) rethrow;
    }
  }

  void _renew(MspEndpoint endpoint) {
    if (!_active) return;
    unawaited(_queueWrite(endpoint, _generation).catchError((Object error) {
      stderr.writeln('[msp] 节点 $nodeId 续租失败：$error');
    }));
  }
}
