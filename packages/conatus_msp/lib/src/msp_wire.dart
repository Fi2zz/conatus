import 'dart:convert';
import 'dart:typed_data';

import 'msp_connection.dart';
import 'msp_signal.dart';

Uint8List encodeMspSignal(MspSignal signal) =>
    Uint8List.fromList(utf8.encode(jsonEncode(signal.toJson())));

MspSignal decodeMspSignal(Uint8List frame) {
  final Object? decoded = jsonDecode(utf8.decode(frame));
  if (decoded is! Map) throw const FormatException('MSP 消息必须为 JSON 对象');
  return MspSignal.fromJson(Map<String, Object?>.from(decoded));
}

void sendMspSignal(MspConnection connection, MspSignal signal) {
  connection.send(encodeMspSignal(signal));
}
