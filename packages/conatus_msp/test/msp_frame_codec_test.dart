import 'dart:typed_data';

import 'package:conatus_msp/src/msp_frame_codec.dart';
import 'package:test/test.dart';

void main() {
  test('帧编码使用四字节大端长度且不含帧头', () {
    final Uint8List frame =
        MspFrameCodec.encode(Uint8List.fromList(<int>[1, 2]));

    expect(frame, <int>[0, 0, 0, 2, 1, 2]);
  });

  test('解码器拆分粘包并等待半包', () {
    final MspFrameDecoder decoder = MspFrameDecoder();
    final Uint8List frames = Uint8List.fromList(<int>[
      ...MspFrameCodec.encode(Uint8List.fromList(<int>[7])),
      ...MspFrameCodec.encode(Uint8List.fromList(<int>[8, 9])),
    ]);

    expect(decoder.add(frames.sublist(0, 3)), isEmpty);
    expect(decoder.add(frames.sublist(3)), <Uint8List>[
      Uint8List.fromList(<int>[7]),
      Uint8List.fromList(<int>[8, 9]),
    ]);
  });

  test('零长度帧是有效消息', () {
    final MspFrameDecoder decoder = MspFrameDecoder();

    expect(decoder.add(MspFrameCodec.encode(Uint8List(0))), hasLength(1));
    expect(decoder.add(Uint8List(0)), isEmpty);
  });

  test('超过十六 MiB 的声明长度会失败', () {
    final Uint8List header = Uint8List(4);
    ByteData.sublistView(header).setUint32(0, 16777217);

    expect(
        () => MspFrameDecoder().add(header), throwsA(isA<FormatException>()));
  });
}
