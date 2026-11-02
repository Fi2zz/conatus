import 'dart:async';
import 'dart:io';

import 'package:conatus_msp/src/msp_directory_presence.dart';
import 'package:conatus_msp/src/msp_endpoint.dart';
import 'package:test/test.dart';

void main() {
  test('withdraw 等待在途续写且声明不会复活', () async {
    final Directory directory =
        Directory.systemTemp.createTempSync('msp-presence-race-');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
    final Completer<void> writeEntered = Completer<void>();
    final Completer<void> releaseWrite = Completer<void>();
    final MspDirectoryPresence presence = MspDirectoryPresence(
      nodeId: 'node_a',
      directory: directory,
      config: MspDirectoryPresenceConfig(
        beforeWrite: () {
          if (!writeEntered.isCompleted) writeEntered.complete();
          return releaseWrite.future;
        },
      ),
    );
    const MspEndpoint endpoint = MspEndpoint(nodeId: 'node_a', port: 1234);

    final Future<void> announcing = presence.announce(endpoint);
    await writeEntered.future.timeout(const Duration(seconds: 1));
    final Future<void> withdrawing = presence.withdraw();
    releaseWrite.complete();
    await Future.wait(<Future<void>>[announcing, withdrawing]);

    expect(File('${directory.path}/node_a.json').existsSync(), isFalse);
    await presence.withdraw();
  });
}
