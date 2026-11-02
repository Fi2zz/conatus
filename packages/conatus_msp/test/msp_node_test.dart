import 'dart:async';
import 'dart:io';

import 'package:conatus_msp/src/msp_manifest.dart';
import 'package:conatus_msp/src/msp_node.dart';
import 'package:conatus_msp/src/msp_signal.dart';
import 'package:conatus_msp/src/msp_tool_result.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late List<MspNode> nodes;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('conatus-msp-node-');
    nodes = <MspNode>[];
  });

  tearDown(() async {
    for (final MspNode node in nodes) {
      await node.stop();
    }
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });

  MspNode createNode(String nodeId) {
    final MspNode node = MspNode(
      nodeId: nodeId,
      nodesDirectory: directory,
      timings: const MspNodeTimings(
        discoveryPoll: Duration(milliseconds: 20),
        staleAfter: Duration(seconds: 2),
        callTimeout: Duration(milliseconds: 100),
        heartbeatInterval: Duration(milliseconds: 20),
      ),
    );
    nodes.add(node);
    return node;
  }

  test('两个节点自动发现并完成工具调用和主动事件', () async {
    final MspNode provider = createNode('provider');
    provider.registerTool(
      const MspToolDescriptor(name: 'get_weather'),
      (Map<String, Object?> args) => <String, Object?>{
        'location': args['location'],
        'temp_c': 21,
      },
    );
    provider.declareSignal(const MspSignalDescriptor(
      path: 'notify.weather.changed',
    ));
    final MspNode consumer = createNode('consumer');
    await provider.start();
    await consumer.start();
    await _waitFor(() => consumer.neighbors.contains('provider'));

    final MspToolResult result = await consumer.call(
      'provider',
      'get_weather',
      <String, Object?>{'location': '杭州'},
    );
    expect(result.failed, isFalse);
    expect(
        result.structured, <String, Object?>{'location': '杭州', 'temp_c': 21});
    expect(result.text, contains('杭州'));

    final Completer<MspSignal> received = Completer<MspSignal>();
    consumer.on('notify.weather.*', received.complete);
    await provider.publish('notify.weather.changed', <String, Object?>{
      'temp_c': 22,
    });
    final MspSignal signal =
        await received.future.timeout(const Duration(seconds: 1));
    expect(signal.source, 'provider');
    expect(signal.payload['temp_c'], 22);
  });

  test('同一连接的响应按 reqid 关联而不按返回顺序', () async {
    final MspNode provider = createNode('provider');
    provider.registerTool(
      const MspToolDescriptor(name: 'delayed_value'),
      (Map<String, Object?> args) => Future<Object?>.delayed(
        Duration(milliseconds: args['delay'] as int),
        () => args['value'],
      ),
    );
    final MspNode consumer = createNode('consumer');
    await provider.start();
    await consumer.start();
    await _waitFor(() => consumer.neighbors.contains('provider'));

    final Future<MspToolResult> slow = consumer.call(
      'provider',
      'delayed_value',
      <String, Object?>{'delay': 60, 'value': 'slow'},
    );
    final Future<MspToolResult> fast = consumer.call(
      'provider',
      'delayed_value',
      <String, Object?>{'delay': 1, 'value': 'fast'},
    );
    expect((await fast).structured, 'fast');
    expect((await slow).structured, 'slow');
  });

  test('超时返回错误值且迟到响应不污染后续调用', () async {
    final MspNode provider = createNode('provider');
    provider.registerTool(
      const MspToolDescriptor(name: 'delayed_value'),
      (Map<String, Object?> args) => Future<Object?>.delayed(
        Duration(milliseconds: args['delay'] as int),
        () => args['value'],
      ),
    );
    final MspNode consumer = createNode('consumer');
    await provider.start();
    await consumer.start();
    await _waitFor(() => consumer.neighbors.contains('provider'));

    final MspToolResult timeout = await consumer.call(
      'provider',
      'delayed_value',
      <String, Object?>{'delay': 150, 'value': 'late'},
    );
    expect(timeout.failed, isTrue);
    expect(timeout.error, contains('超时'));
    final MspToolResult next = await consumer.call(
      'provider',
      'delayed_value',
      <String, Object?>{'delay': 1, 'value': 'next'},
    );
    expect(next.structured, 'next');
  });

  test('对端停止会唤醒等待中的调用', () async {
    final MspNode provider = createNode('provider');
    provider.registerTool(
      const MspToolDescriptor(name: 'never_finishes'),
      (Map<String, Object?> args) => Completer<Object?>().future,
    );
    final MspNode consumer = createNode('consumer');
    await provider.start();
    await consumer.start();
    await _waitFor(() => consumer.neighbors.contains('provider'));

    final Future<MspToolResult> pending = consumer.call(
      'provider',
      'never_finishes',
      <String, Object?>{},
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await provider.stop();
    expect((await pending).failed, isTrue);
  });
}

Future<void> _waitFor(bool Function() condition) async {
  final DateTime deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) throw TimeoutException('等待节点发现超时');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
