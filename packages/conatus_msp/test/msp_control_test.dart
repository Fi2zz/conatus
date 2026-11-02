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
  test('pong 是合法控制消息且不会触发协议错误', () async {
    final Directory directory =
        Directory.systemTemp.createTempSync('msp-control-');
    final MspNode provider =
        MspNode(nodeId: 'provider', nodesDirectory: directory);
    await provider.start();
    addTearDown(() async {
      await provider.stop();
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    final Map<String, Object?> address = _readAddress(directory);
    final Socket socket = await Socket.connect(
      address['host'] as String,
      address['port'] as int,
    );
    final StreamController<MspSignal> frames = StreamController<MspSignal>();
    late final MspConnection connection;
    connection = MspConnection(
      socket,
      (Uint8List frame) => frames.add(decodeMspSignal(frame)),
      () {},
    );
    final StreamIterator<MspSignal> iterator =
        StreamIterator<MspSignal>(frames.stream);
    addTearDown(() async {
      await iterator.cancel();
      await connection.close();
      await frames.close();
    });
    connection.send(encodeMspSignal(MspSignal(
      type: 'hello',
      source: 'raw_peer',
      options: MspSignalOptions()
        ..payload = <String, Object?>{
          'manifest': MspManifest().toJson(),
        },
    )));
    await iterator.moveNext().timeout(const Duration(seconds: 1));
    expect(iterator.current.type, 'ack');

    connection
        .send(encodeMspSignal(MspSignal(type: 'pong', source: 'raw_peer')));
    await expectLater(
      iterator.moveNext().timeout(const Duration(milliseconds: 50)),
      throwsA(isA<TimeoutException>()),
    );
  });
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
