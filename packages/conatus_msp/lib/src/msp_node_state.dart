import 'dart:async';
import 'dart:io';

import 'msp_connection.dart';
import 'msp_directory_discovery.dart';
import 'msp_directory_presence.dart';
import 'msp_endpoint.dart';
import 'msp_manifest.dart';
import 'msp_pending_calls.dart';
import 'msp_signal_handlers.dart';

class MspNodeTimings {
  const MspNodeTimings({
    this.discoveryPoll = const Duration(seconds: 30),
    this.staleAfter = const Duration(seconds: 30),
    this.callTimeout = const Duration(seconds: 5),
    this.heartbeatInterval = const Duration(seconds: 15),
  });

  final Duration discoveryPoll;
  final Duration staleAfter;
  final Duration callTimeout;
  final Duration heartbeatInterval;
}

typedef MspToolHandler = FutureOr<Object?> Function(Map<String, Object?> args);

class MspPeerChannel {
  MspPeerChannel(this.connection, this.outbound);

  final MspConnection connection;
  final bool outbound;
  final Completer<void> ready = Completer<void>();
  String? peerId;
}

class MspNodeState {
  MspNodeState({
    required this.nodeId,
    required this.nodesDirectory,
    required this.timings,
  });

  final String nodeId;
  final Directory nodesDirectory;
  final MspNodeTimings timings;
  final MspManifest manifest = _createManifest();
  final Map<String, MspToolHandler> tools = <String, MspToolHandler>{};
  final Map<String, MspEndpoint> endpoints = <String, MspEndpoint>{};
  final Map<String, MspConnection> connections = <String, MspConnection>{};
  final Map<String, MspManifest> peerManifests = <String, MspManifest>{};
  final Map<String, DateTime> lastSeen = <String, DateTime>{};
  final Map<String, Future<MspConnection>> dials =
      <String, Future<MspConnection>>{};
  final Map<MspConnection, MspPeerChannel> channels =
      <MspConnection, MspPeerChannel>{};
  final MspPendingCalls pending = MspPendingCalls();
  final MspSignalHandlers handlers = MspSignalHandlers();
  ServerSocket? server;
  MspDirectoryDiscovery? discovery;
  MspDirectoryPresence? presence;
  Timer? heartbeat;
  bool running = false;
  int generation = 0;
}

MspManifest _createManifest() => MspManifest()
  ..patterns.addAll(<String>['msp/request-reply', 'msp/publish-subscribe'])
  ..capabilities.addAll(<String>{'pub', 'sub', 'req', 'rep'});
