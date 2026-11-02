import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'msp_frame_codec.dart';

typedef MspFrameHandler = void Function(Uint8List frame);
typedef MspClosedHandler = void Function();

class MspConnection {
  MspConnection(this._socket, this.onFrame, this.onClosed) {
    _subscription = _socket.listen(
      _handleData,
      onError: _handleError,
      onDone: close,
    );
  }

  final Socket _socket;
  final MspFrameHandler onFrame;
  final MspClosedHandler onClosed;
  final MspFrameDecoder _decoder = MspFrameDecoder();
  late final StreamSubscription<Uint8List> _subscription;
  bool _closed = false;

  bool get closed => _closed;

  void send(Uint8List payload) {
    if (_closed) throw StateError('MSP 连接已关闭');
    _socket.add(MspFrameCodec.encode(payload));
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _subscription.cancel();
    await _socket.close();
    onClosed();
  }

  void _handleData(Uint8List data) {
    try {
      for (final Uint8List frame in _decoder.add(data)) {
        onFrame(frame);
      }
    } on FormatException {
      unawaited(close());
    }
  }

  void _handleError(Object error) => unawaited(close());
}
