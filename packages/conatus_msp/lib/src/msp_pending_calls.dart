import 'dart:async';
import 'dart:math';

import 'msp_signal.dart';
import 'msp_tool_result.dart';

class MspPendingRequest {
  MspPendingRequest(this.id, this.peerId);

  final String id;
  final String peerId;
  final Completer<MspToolResult> completer = Completer<MspToolResult>();
}

class MspPendingCalls {
  final Map<String, MspPendingRequest> _requests =
      <String, MspPendingRequest>{};
  final Random _random = Random.secure();

  MspPendingRequest create(String peerId) {
    final MspPendingRequest request = MspPendingRequest(_newId(), peerId);
    _requests[request.id] = request;
    return request;
  }

  void complete(MspSignal signal) {
    final String? id = signal.reqid;
    if (id == null) return;
    final MspPendingRequest? request = _requests.remove(id);
    request?.completer.complete(MspToolResult.fromPayload(signal.payload));
  }

  void remove(String id) => _requests.remove(id);

  void failPeer(String peerId, String message) {
    final List<MspPendingRequest> requests = _requests.values
        .where((MspPendingRequest item) => item.peerId == peerId)
        .toList();
    for (final MspPendingRequest request in requests) {
      _requests.remove(request.id);
      request.completer.complete(MspToolResult.failure(message));
    }
  }

  void failAll(String message) {
    final List<MspPendingRequest> requests = _requests.values.toList();
    _requests.clear();
    for (final MspPendingRequest request in requests) {
      request.completer.complete(MspToolResult.failure(message));
    }
  }

  String _newId() {
    String id = _randomHex();
    while (_requests.containsKey(id)) {
      id = _randomHex();
    }
    return id;
  }

  String _randomHex() => List<int>.generate(
        8,
        (_) => _random.nextInt(256),
      ).map((int byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}
