import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'msp_endpoint.dart';

class MspDirectoryPresence {
  MspDirectoryPresence({
    required this.nodeId,
    required this.directory,
    this.renewInterval = const Duration(seconds: 10),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final String nodeId;
  final Directory directory;
  final Duration renewInterval;
  final DateTime Function() _clock;
  Timer? _renewTimer;

  Future<void> announce(MspEndpoint endpoint) async {
    await _write(endpoint);
    _renewTimer?.cancel();
    _renewTimer = Timer.periodic(renewInterval, (_) => _renew(endpoint));
  }

  Future<void> withdraw() async {
    _renewTimer?.cancel();
    _renewTimer = null;
    final File file = _declarationFile;
    if (file.existsSync()) await file.delete();
  }

  File get _declarationFile => File('${directory.path}/$nodeId.json');

  Future<void> _write(MspEndpoint endpoint) async {
    directory.createSync(recursive: true);
    final double timestamp = _clock().microsecondsSinceEpoch / 1000000;
    final File temporary = File('${_declarationFile.path}.tmp');
    await temporary
        .writeAsString(jsonEncode(endpoint.toDeclaration(timestamp)));
    await temporary.rename(_declarationFile.path);
  }

  void _renew(MspEndpoint endpoint) {
    unawaited(_write(endpoint).catchError((Object error) {
      stderr.writeln('[msp] 节点 $nodeId 续租失败：$error');
    }));
  }
}
