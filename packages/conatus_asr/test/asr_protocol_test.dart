import 'dart:convert';
import 'dart:typed_data';

import 'package:conatus_asr/conatus_asr.dart';
import 'package:test/test.dart';

void main() {
  group('buildAsrFrame / decodeAsrFrame', () {
    test('full client request round-trip', () {
      final Uint8List frame =
          buildFullClientRequest(<String, Object?>{'model_name': 'bigmodel'});

      final AsrFrame decoded = decodeAsrFrame(frame);
      expect(decoded.messageType, asrMessageFullClientRequest);
      expect(decoded.serialization, asrSerializationJson);
      expect(decoded.compression, asrCompressionNone);
      expect(decoded.sequence, isNull);
      expect(decoded.isError, isFalse);
      expect(decoded.isLast, isFalse);
      expect(
        jsonDecode(utf8.decode(decoded.payload)),
        <String, Object?>{'model_name': 'bigmodel'},
      );
    });

    test('audio frame 携带正 sequence，末包为负 sequence', () {
      final AsrFrame data =
          decodeAsrFrame(buildAudioFrame(<int>[1, 2, 3], sequence: 2));
      expect(data.messageType, asrMessageAudioOnly);
      expect(data.serialization, asrSerializationNone);
      expect(data.sequence, 2);
      expect(data.payload, <int>[1, 2, 3]);
      expect(data.isLast, isFalse);

      final AsrFrame last = decodeAsrFrame(
        buildAudioFrame(<int>[4], sequence: 3, last: true),
      );
      expect(last.sequence, -3);
      expect(last.isLast, isTrue);
    });

    test('gzip 压缩往返', () {
      final Uint8List frame =
          buildAudioFrame(<int>[9, 8, 7], sequence: 1, compress: true);
      final AsrFrame decoded = decodeAsrFrame(frame);
      expect(decoded.compression, asrCompressionGzip);
      expect(decoded.payload, <int>[9, 8, 7]);

      final DecodedJson request = DecodedJson(
        buildFullClientRequest(<String, Object?>{'k': 'v'}, compress: true),
      );
      expect(request.frame.compression, asrCompressionGzip);
      expect(request.json['k'], 'v');
    });

    test('错误帧与 JSON 负载', () {
      final Uint8List raw = buildAsrFrame(
        messageType: asrMessageError,
        flags: 0,
        serialization: asrSerializationJson,
        compression: asrCompressionNone,
        payload: utf8.encode(jsonEncode(<String, Object?>{'message': 'bad'})),
      );
      final AsrFrame frame = decodeAsrFrame(raw);
      expect(frame.isError, isTrue);
      expect(decodeAsrJson(frame)?['message'], 'bad');
    });

    test('非法帧抛 AsrException', () {
      expect(
          () => decodeAsrFrame(<int>[0, 1, 2]), throwsA(isA<AsrException>()));
    });
  });
}

/// 小工具：一次拿到帧与解析后的 JSON。
class DecodedJson {
  DecodedJson(this.raw);

  final Uint8List raw;

  AsrFrame get frame => decodeAsrFrame(raw);

  Map<String, dynamic> get json => decodeAsrJson(frame)!;
}
