import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:conatus_core/conatus_core.dart';

import 'msp_connection.dart';
import 'msp_directory_discovery.dart';
import 'msp_directory_presence.dart';
import 'msp_endpoint.dart';
import 'msp_manifest.dart';
import 'msp_node_state.dart';
import 'msp_pending_calls.dart';
import 'msp_signal.dart';
import 'msp_signal_handlers.dart';
import 'msp_tool_result.dart';
import 'msp_wire.dart';

export 'msp_node_state.dart' show MspNodeTimings;

part 'msp_node_lifecycle.dart';
part 'msp_node_messages.dart';
part 'msp_node_calls.dart';
part 'msp_node_heartbeat.dart';

class MspNode {
  MspNode({
    required String nodeId,
    Directory? nodesDirectory,
    MspNodeTimings timings = const MspNodeTimings(),
  }) : _state = MspNodeState(
          nodeId: nodeId,
          nodesDirectory: nodesDirectory ?? _defaultNodesDirectory(),
          timings: timings,
        );

  final MspNodeState _state;

  bool get running => _state.running;

  List<String> get neighbors => List<String>.unmodifiable(
        _state.connections.keys,
      );

  void registerTool(MspToolDescriptor descriptor, MspToolHandler handler) {
    if (_state.running) throw StateError('节点启动后暂不支持动态注册工具');
    _state.manifest.addTool(descriptor);
    _state.tools[descriptor.name] = handler;
  }

  void declareSignal(MspSignalDescriptor descriptor) {
    if (_state.running) throw StateError('节点启动后暂不支持动态声明信号');
    _state.manifest.addSignal(descriptor);
  }

  Disposer on(String? pattern, MspSignalHandler handler) =>
      _state.handlers.add(pattern, handler);

  Future<void> start() => startMspNode(_state);
  Future<void> stop() => stopMspNode(_state);

  Future<MspToolResult> call(
    String peerId,
    String tool,
    Map<String, Object?> args,
  ) =>
      callMspTool(_state, peerId, tool, args);

  Future<void> publish(String path, Map<String, Object?> payload) =>
      publishMspSignal(_state, path, payload);
}

Directory _defaultNodesDirectory() {
  final String home = Platform.environment['HOME'] ?? Directory.current.path;
  return Directory('$home/.msp/nodes');
}
