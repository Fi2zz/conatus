import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:conatus_msp/src/msp_connection.dart';
import 'package:conatus_msp/src/msp_node.dart';
import 'package:conatus_msp/src/msp_node_state.dart';
import 'package:conatus_msp/src/msp_tool_result.dart';
import 'package:test/test.dart';

void main() {
  test('关闭连接上的调用返回错误值而不抛出', () async {
    final ServerSocket server =
        await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final Socket socket =
        await Socket.connect(InternetAddress.loopbackIPv4, server.port);
    final Socket accepted = await server.first;
    final MspConnection connection = MspConnection(socket, (_) {}, () {});
    await connection.close();
    final MspNodeState state = MspNodeState(
      nodeId: 'consumer',
      nodesDirectory: Directory.systemTemp,
      timings: const MspNodeTimings(),
    );
    state.connections['peer'] = connection;
    addTearDown(() async {
      await accepted.close();
      await server.close();
    });

    final MspToolResult result = await callMspTool(
      state,
      'peer',
      'get_weather',
      <String, Object?>{},
    );
    expect(result.failed, isTrue);
  });

  test('停止会唤醒无 ACK 的在途调用且不留下 channel', () async {
    final Directory directory =
        Directory.systemTemp.createTempSync('msp-no-ack-');
    final ServerSocket server =
        await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final Completer<void> accepted = Completer<void>();
    final List<Socket> sockets = <Socket>[];
    server.listen((Socket socket) {
      sockets.add(socket);
      if (!accepted.isCompleted) accepted.complete();
    });
    File('${directory.path}/silent.json').writeAsStringSync(jsonEncode(
      <String, Object?>{
        'node_id': 'silent',
        'endpoint': <String, Object?>{
          'transport_type': 'tcp',
          'address': <String, Object?>{
            'host': '127.0.0.1',
            'port': server.port,
          },
        },
        'timestamp': DateTime.now().microsecondsSinceEpoch / 1000000,
      },
    ));
    final MspNode node = MspNode(nodeId: 'consumer', nodesDirectory: directory);
    addTearDown(() async {
      await node.stop();
      for (final Socket socket in sockets) {
        await socket.close();
      }
      await server.close();
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    await node.start();

    final Future<MspToolResult> call =
        node.call('silent', 'never_ack', <String, Object?>{});
    await accepted.future.timeout(const Duration(seconds: 1));
    await node.stop();
    final MspToolResult result = await call.timeout(const Duration(seconds: 1));
    expect(result.failed, isTrue);
    expect(node.neighbors, isEmpty);
  });
}
