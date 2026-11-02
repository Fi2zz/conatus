import 'dart:async';
import 'dart:io';

import 'package:conatus_msp/src/msp_connection.dart';
import 'package:conatus_msp/src/msp_endpoint.dart';
import 'package:conatus_msp/src/msp_node.dart';
import 'package:conatus_msp/src/msp_node_state.dart';
import 'package:test/test.dart';

void main() {
  test('同一 peer 并发拨号共享一条连接', () async {
    final ServerSocket server =
        await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final List<Socket> accepted = <Socket>[];
    final Completer<void> firstAccepted = Completer<void>();
    server.listen((Socket socket) {
      accepted.add(socket);
      if (!firstAccepted.isCompleted) firstAccepted.complete();
    });
    final MspNodeState state = MspNodeState(
      nodeId: 'consumer',
      nodesDirectory: Directory.systemTemp,
      timings: const MspNodeTimings(),
    )..running = true;
    state.endpoints['peer'] = MspEndpoint(nodeId: 'peer', port: server.port);
    addTearDown(() async {
      await stopMspNode(state);
      for (final Socket socket in accepted) {
        await socket.close();
      }
      await server.close();
    });

    final Future<MspConnection> first = connectMspPeer(state, 'peer');
    final Future<MspConnection> second = connectMspPeer(state, 'peer');
    await firstAccepted.future.timeout(const Duration(seconds: 1));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(accepted, hasLength(1));

    await stopMspNode(state);
    await expectLater(first, throwsStateError);
    await expectLater(second, throwsStateError);
  });
}
