import 'dart:async';
import 'dart:io';

import 'package:conatus_msp/conatus_msp.dart';

Future<void> main() async {
  final Directory directory =
      Directory.systemTemp.createTempSync('conatus-msp-demo-');
  try {
    await _runDemo(directory);
    print('[4/4] 清理完成：临时目录已删除');
  } finally {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  }
}

Future<void> _runDemo(Directory directory) async {
  const MspNodeTimings timings = MspNodeTimings(
    discoveryPoll: Duration(milliseconds: 20),
    heartbeatInterval: Duration(milliseconds: 50),
  );
  final MspNode provider = MspNode(
    nodeId: 'provider',
    nodesDirectory: directory,
    timings: timings,
  );
  final MspNode consumer = MspNode(
    nodeId: 'consumer',
    nodesDirectory: directory,
    timings: timings,
  );
  _registerWeather(provider);
  try {
    await provider.start();
    await consumer.start();
    await _waitForNeighbor(consumer);
    print('[1/4] 自动发现：consumer → provider（未配置端口）');
    await _callWeather(consumer);
    await _receiveWeatherEvent(provider, consumer);
  } finally {
    await consumer.stop();
    await provider.stop();
  }
}

void _registerWeather(MspNode provider) {
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
}

Future<void> _callWeather(MspNode consumer) async {
  final MspToolResult result = await consumer.call(
    'provider',
    'get_weather',
    <String, Object?>{'location': '杭州'},
  );
  if (result.failed) throw StateError(result.error);
  final Map<String, Object?> weather =
      result.structured as Map<String, Object?>;
  print('[2/4] 工具调用：杭州 ${weather['temp_c']}°C');
}

Future<void> _receiveWeatherEvent(MspNode provider, MspNode consumer) async {
  final Completer<MspSignal> received = Completer<MspSignal>();
  consumer.on('notify.weather.*', received.complete);
  await provider
      .publish('notify.weather.changed', <String, Object?>{'temp_c': 22});
  final MspSignal signal =
      await received.future.timeout(const Duration(seconds: 2));
  print('[3/4] 主动事件：${signal.path}，temp_c=${signal.payload['temp_c']}');
}

Future<void> _waitForNeighbor(MspNode consumer) async {
  final DateTime deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!consumer.neighbors.contains('provider')) {
    if (DateTime.now().isAfter(deadline)) throw TimeoutException('节点发现超时');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
