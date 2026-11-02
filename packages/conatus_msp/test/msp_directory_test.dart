import 'dart:convert';
import 'dart:io';

import 'package:conatus_msp/src/msp_directory_discovery.dart';
import 'package:conatus_msp/src/msp_directory_presence.dart';
import 'package:conatus_msp/src/msp_endpoint.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late DateTime now;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('conatus-msp-directory-');
    now = DateTime.utc(2026);
  });

  tearDown(() {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });

  test('Presence 原子写声明且撤销幂等', () async {
    final MspDirectoryPresence presence = MspDirectoryPresence(
      nodeId: 'node_a',
      directory: directory,
      config: MspDirectoryPresenceConfig(clock: () => now),
    );
    const MspEndpoint endpoint = MspEndpoint(nodeId: 'node_a', port: 45678);

    await presence.announce(endpoint);
    final File declaration = File('${directory.path}/node_a.json');
    expect(declaration.existsSync(), isTrue);
    expect(File('${directory.path}/node_a.json.tmp').existsSync(), isFalse);
    expect(jsonDecode(declaration.readAsStringSync()), <String, Object?>{
      'node_id': 'node_a',
      'endpoint': <String, Object?>{
        'transport_type': 'tcp',
        'address': <String, Object?>{'host': '127.0.0.1', 'port': 45678},
      },
      'timestamp': 1767225600.0,
    });

    await presence.withdraw();
    await presence.withdraw();
    expect(declaration.existsSync(), isFalse);
  });

  test('Discovery 跳过自身损坏与过期声明并通知消失', () {
    final List<MspEndpoint> added = <MspEndpoint>[];
    final List<String> removed = <String>[];
    final MspDirectoryDiscovery discovery = MspDirectoryDiscovery(
      selfNodeId: 'consumer',
      directory: directory,
      clock: () => now,
    );
    _writeDeclaration(directory, 'consumer', 1001, now);
    _writeDeclaration(directory, 'provider', 1002, now);
    _writeDeclaration(
        directory, 'stale', 1003, now.subtract(const Duration(seconds: 31)));
    File('${directory.path}/broken.json').writeAsStringSync('{broken');

    discovery.watch(added.add, removed.add);
    expect(added.map((MspEndpoint item) => item.nodeId), <String>['provider']);

    File('${directory.path}/provider.json').deleteSync();
    discovery.scan();
    expect(removed, <String>['provider']);
    discovery.stop();
  });

  test('缺失 timestamp 的声明不会过期', () {
    File('${directory.path}/manual.json').writeAsStringSync(jsonEncode(
      <String, Object?>{
        'node_id': 'manual',
        'endpoint': <String, Object?>{
          'transport_type': 'tcp',
          'address': <String, Object?>{'host': '127.0.0.1', 'port': 1004},
        },
      },
    ));
    final MspDirectoryDiscovery discovery = MspDirectoryDiscovery(
      selfNodeId: 'consumer',
      directory: directory,
      clock: () => now.add(const Duration(days: 365)),
    );

    expect(discovery.scan().single.nodeId, 'manual');
    discovery.stop();
  });

  test('租约恰好等于阈值时仍然有效', () {
    _writeDeclaration(directory, 'provider', 1005, now);
    now = now.add(const Duration(seconds: 30));
    final MspDirectoryDiscovery discovery = MspDirectoryDiscovery(
      selfNodeId: 'consumer',
      directory: directory,
      clock: () => now,
    );

    expect(discovery.scan(), isNotEmpty);
    now = now.add(const Duration(milliseconds: 1));
    expect(discovery.scan(), isEmpty);
    discovery.stop();
  });
}

void _writeDeclaration(
  Directory directory,
  String nodeId,
  int port,
  DateTime timestamp,
) {
  File('${directory.path}/$nodeId.json').writeAsStringSync(jsonEncode(
    <String, Object?>{
      'node_id': nodeId,
      'endpoint': <String, Object?>{
        'transport_type': 'tcp',
        'address': <String, Object?>{'host': '127.0.0.1', 'port': port},
      },
      'timestamp': timestamp.microsecondsSinceEpoch / 1000000,
    },
  ));
}
