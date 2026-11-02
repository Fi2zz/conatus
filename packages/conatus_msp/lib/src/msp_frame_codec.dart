import 'dart:typed_data';

abstract final class MspFrameCodec {
  static const int maxMessageSize = 16 * 1024 * 1024;

  static Uint8List encode(Uint8List payload) {
    final Uint8List header = Uint8List(4);
    ByteData.sublistView(header).setUint32(0, payload.length);
    return Uint8List.fromList(<int>[...header, ...payload]);
  }
}

class MspFrameDecoder {
  final List<int> _buffer = <int>[];

  List<Uint8List> add(Uint8List chunk) {
    _buffer.addAll(chunk);
    return _drainFrames();
  }

  List<Uint8List> _drainFrames() {
    final List<Uint8List> frames = <Uint8List>[];
    while (_buffer.length >= 4) {
      final int length = _readLength();
      if (length > MspFrameCodec.maxMessageSize) {
        throw const FormatException('MSP 帧超过 16 MiB 上限');
      }
      if (_buffer.length < length + 4) break;
      frames.add(Uint8List.fromList(_buffer.sublist(4, length + 4)));
      _buffer.removeRange(0, length + 4);
    }
    return frames;
  }

  int _readLength() {
    final Uint8List header = Uint8List.fromList(_buffer.take(4).toList());
    return ByteData.sublistView(header).getUint32(0);
  }
}
