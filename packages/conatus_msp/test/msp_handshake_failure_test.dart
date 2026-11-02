import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:conatus_msp/src/msp_connection.dart';
import 'package:conatus_msp/src/msp_manifest.dart';
import 'package:conatus_msp/src/msp_node.dart';
import 'package:conatus_msp/src/msp_signal.dart';
import 'package:conatus_msp/src/msp_wire.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late MspNode provider;

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('msp-handshake-');
    provider = MspNode(
      nodeId: 'provider',
      nodesDirectory: directory,
      timings:
          const MspNodeTimings(heartbeatInterval: Duration(milliseconds: 20)),
    );
    await provider.start();
  });

  tearDown(() async {
    await provider.stop();
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });

  test('缺少 Manifest 的握手不会注册可用节点', () async {
    final _RawPeer peer = await _RawPeer.connect(directory);
    addTearDown(peer.close);
    peer.send('hello', includeManifest: false);

    await peer.closed.future.timeout(const Duration(seconds: 1));
    expect(provider.neighbors, isEmpty);
  });

  test('静默连接超过心跳窗口后会关闭并移除节点', () async {
    final _RawPeer peer = await _RawPeer.connect(directory);
    addTearDown(peer.close);
    peer.send('hello');
    await peer.next().timeout(const Duration(seconds: 1));
    expect(provider.neighbors, <String>['raw_peer']);

    await peer.closed.future.timeout(const Duration(milliseconds: 200));
    expect(provider.neighbors, isEmpty);
  });
}

class _RawPeer {
  _RawPeer(this.connection, this.frames, this.closed);

  static Future<_RawPeer> connect(Directory directory) async {
    final Map<String, Object?> address = _readAddress(directory);
    final Socket socket = await Socket.connect(
      address['host'] as String,
      address['port'] as int,
    );
    final Completer<void> closed = Completer<void>();
    final StreamController<MspSignal> frames = StreamController<MspSignal>();
    late final MspConnection connection;
    connection = MspConnection(
      socket,
      (Uint8List frame) => frames.add(decodeMspSignal(frame)),
      () {
        if (!closed.isCompleted) closed.complete();
      },
    );
    return _RawPeer(connection, frames, closed);
  }

  final MspConnection connection;
  final StreamController<MspSignal> frames;
  final Completer<void> closed;

  void send(String type, {bool includeManifest = true}) {
    final MspSignalOptions options = MspSignalOptions();
    if (includeManifest) {
      options.payload = <String, Object?>{'manifest': MspManifest().toJson()};
    }
    connection.send(encodeMspSignal(MspSignal(
      type: type,
      source: 'raw_peer',
      options: options,
    )));
  }

  Future<MspSignal> next() => frames.stream.first;

  Future<void> close() => connection.close();
}

Map<String, Object?> _readAddress(Directory directory) {
  final Object? decoded = jsonDecode(
    File('${directory.path}/provider.json').readAsStringSync(),
  );
  final Map<String, Object?> declaration =
      Map<String, Object?>.from(decoded as Map);
  final Map<String, Object?> endpoint = Map<String, Object?>.from(
    declaration['endpoint'] as Map<String, Object?>,
  );
  return Map<String, Object?>.from(endpoint['address'] as Map<String, Object?>);
}
