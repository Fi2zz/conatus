/// 火山/豆包流式 ASR（SAUC）WebSocket 二进制协议编解码。
///
/// 帧 = 4 字节 header +（可选 4 字节 sequence）+ 4 字节大端 payload 长度 + payload，
/// 整数一律大端。协议详见
/// <https://www.volcengine.com/docs/6561/1354869>。本层只处理字节，不涉及网络，
/// 因此可独立单测。
library;

import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:typed_data';

import 'asr_types.dart';

/// 协议版本（目前仅 1）。
const int asrProtocolVersion = 0x01;

/// header 长度，单位为 4 字节（1 → 4 字节）。
const int asrHeaderSize = 0x01;

/// 消息类型：端上发送含请求参数的 full client request。
const int asrMessageFullClientRequest = 0x01;

/// 消息类型：端上发送音频数据的 audio only request。
const int asrMessageAudioOnly = 0x02;

/// 消息类型：服务端下发的 full server response。
const int asrMessageFullServerResponse = 0x09;

/// 消息类型：服务端错误。
const int asrMessageError = 0x0F;

/// 序列化：无序列化（原始字节）。
const int asrSerializationNone = 0x00;

/// 序列化：JSON。
const int asrSerializationJson = 0x01;

/// 压缩：不压缩。
const int asrCompressionNone = 0x00;

/// 压缩：gzip。
const int asrCompressionGzip = 0x01;

/// 消息 flags：header 后 4 字节为正 sequence。
const int asrFlagSequence = 0x01;

/// 消息 flags：最后一包（不携带 sequence）。
const int asrFlagLast = 0x02;

/// 消息 flags：最后一包，header 后 4 字节为负 sequence。
const int asrFlagLastSequence = 0x03;

/// 一帧解码后的协议数据。
class AsrFrame {
  const AsrFrame({
    required this.messageType,
    required this.flags,
    required this.serialization,
    required this.compression,
    this.sequence,
    this.payload = const <int>[],
  });

  /// 消息类型（[asrMessageFullClientRequest] 等）。
  final int messageType;

  /// 消息类型补充 flags（[asrFlagSequence] 等）。
  final int flags;

  /// 序列化方式。
  final int serialization;

  /// 压缩方式。
  final int compression;

  /// 序列号；未携带时为 `null`。
  final int? sequence;

  /// 已解压的负载字节。
  final List<int> payload;

  /// 是否为错误帧。
  bool get isError => messageType == asrMessageError;

  /// 是否为服务端识别的最后一帧。
  bool get isLast => (flags & asrFlagLast) != 0;

  @override
  String toString() =>
      'AsrFrame(type=$messageType, flags=$flags, seq=$sequence, '
      'payload=${payload.length}B)';
}

/// 编解码一帧。[sequence] 非空时写入 4 字节大端有符号序列号。
Uint8List buildAsrFrame({
  required int messageType,
  required int flags,
  required int serialization,
  required int compression,
  required List<int> payload,
  int? sequence,
}) {
  final bool hasSequence = sequence != null;
  final int headerBytes = (asrHeaderSize * 4) + (hasSequence ? 4 : 0);
  final Uint8List frame = Uint8List(headerBytes + 4 + payload.length);
  frame[0] = (asrProtocolVersion << 4) | asrHeaderSize;
  frame[1] = (messageType << 4) | flags;
  frame[2] = (serialization << 4) | compression;
  frame[3] = 0x00;

  final ByteData view = ByteData.view(frame.buffer);
  int offset = 4;
  if (hasSequence) {
    view.setInt32(offset, sequence);
    offset += 4;
  }
  view.setUint32(offset, payload.length);
  offset += 4;
  frame.setRange(offset, offset + payload.length, payload);
  return frame;
}

/// 解码一帧（按 compression 自动解压 payload）。
///
/// 帧结构非法时抛 [AsrException]。
AsrFrame decodeAsrFrame(List<int> bytes) {
  final Uint8List buffer =
      bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
  if (buffer.length < 8) {
    throw AsrException('ASR 帧过短：${buffer.length} 字节');
  }
  final int version = buffer[0] >> 4;
  final int headerSize = (buffer[0] & 0x0F) * 4;
  final int messageType = buffer[1] >> 4;
  final int flags = buffer[1] & 0x0F;
  final int serialization = buffer[2] >> 4;
  final int compression = buffer[2] & 0x0F;
  if (version != asrProtocolVersion) {
    throw AsrException('不支持的 ASR 协议版本：$version');
  }
  if (headerSize < 4 || buffer.length < headerSize + 4) {
    throw AsrException('ASR 帧头不完整：${buffer.length} 字节');
  }

  final ByteData view =
      ByteData.view(buffer.buffer, buffer.offsetInBytes, buffer.length);
  int offset = headerSize;
  int? sequence;
  if ((flags & asrFlagSequence) != 0) {
    if (offset + 4 > buffer.length) {
      throw const AsrException('ASR 帧缺少 sequence 字段');
    }
    sequence = view.getInt32(offset);
    offset += 4;
  }
  if (offset + 4 > buffer.length) {
    throw const AsrException('ASR 帧缺少 payload 长度字段');
  }
  final int payloadSize = view.getUint32(offset);
  offset += 4;
  if (offset + payloadSize > buffer.length) {
    throw AsrException(
      'ASR 帧负载不完整：期望 $payloadSize 字节，实际 ${buffer.length - offset}',
    );
  }
  final List<int> raw =
      Uint8List.sublistView(buffer, offset, offset + payloadSize);
  final List<int> payload =
      compression == asrCompressionGzip ? gzip.decode(raw) : raw;
  return AsrFrame(
    messageType: messageType,
    flags: flags,
    serialization: serialization,
    compression: compression,
    sequence: sequence,
    payload: payload,
  );
}

/// 构造 full client request 帧（JSON 负载）。
Uint8List buildFullClientRequest(
  Map<String, Object?> request, {
  bool compress = false,
}) {
  final List<int> payload = utf8.encode(jsonEncode(request));
  return buildAsrFrame(
    messageType: asrMessageFullClientRequest,
    flags: 0,
    serialization: asrSerializationJson,
    compression: compress ? asrCompressionGzip : asrCompressionNone,
    payload: compress ? gzip.encode(payload) : payload,
  );
}

/// 构造 audio-only 帧。[last] 为 true 时以负 sequence 标记最后一包。
Uint8List buildAudioFrame(
  List<int> audio, {
  required int sequence,
  bool last = false,
  bool compress = false,
}) =>
    buildAsrFrame(
      messageType: asrMessageAudioOnly,
      flags: last ? asrFlagLastSequence : asrFlagSequence,
      serialization: asrSerializationNone,
      compression: compress ? asrCompressionGzip : asrCompressionNone,
      sequence: last ? -sequence : sequence,
      payload: compress ? gzip.encode(audio) : audio,
    );

/// 解码服务端帧的 JSON 负载；非 JSON 或解析失败时返回 `null`。
Map<String, dynamic>? decodeAsrJson(AsrFrame frame) {
  if (frame.serialization != asrSerializationJson || frame.payload.isEmpty) {
    return null;
  }
  try {
    final Object? decoded = jsonDecode(utf8.decode(frame.payload));
    return decoded is Map<String, dynamic> ? decoded : null;
  } on FormatException {
    return null;
  }
}
