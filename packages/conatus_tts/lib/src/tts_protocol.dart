/// 火山 v3 TTS WebSocket 二进制协议编解码。
///
/// 帧 = 4 字节 header + 可选字段（sequence / error_code / event / session_id /
/// connect_id）+ 4 字节大端负载长度 + 负载，整数一律大端。编解码只处理字节，
/// 不涉及网络，可独立单测。协议见
/// <https://www.volcengine.com/docs/6561/1719100>。
library;

import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:typed_data';

import 'tts_types.dart';

/// 协议版本（目前仅 1）。
const int ttsProtocolVersion = 0x01;

/// header 长度，单位为 4 字节（1 → 4 字节）。
const int ttsHeaderSize = 0x01;

/// 消息类型：端上 full client request。
const int ttsMsgFullClientRequest = 0x01;

/// 消息类型：服务端 full server response（句信息 / 会话结束）。
const int ttsMsgFullServerResponse = 0x09;

/// 消息类型：服务端音频响应。
const int ttsMsgAudioOnlyServer = 0x0B;

/// 消息类型：服务端错误。
const int ttsMsgError = 0x0F;

/// flags：无 sequence。
const int ttsFlagNoSeq = 0x00;

/// flags：正 sequence。
const int ttsFlagPositiveSeq = 0x01;

/// flags：负 sequence（末包）。
const int ttsFlagNegativeSeq = 0x03;

/// flags：header 后带 event（及 session_id / connect_id）。
const int ttsFlagWithEvent = 0x04;

/// 序列化：原始字节。
const int ttsSerializationRaw = 0x00;

/// 序列化：JSON。
const int ttsSerializationJson = 0x01;

/// 压缩：不压缩。
const int ttsCompressionNone = 0x00;

/// 压缩：gzip。
const int ttsCompressionGzip = 0x01;

/// 事件：会话结束。
const int ttsEventSessionFinished = 152;

/// 事件：句子开始。
const int ttsEventSentenceStart = 350;

/// 事件：句子结束。
const int ttsEventSentenceEnd = 351;

/// 事件：音频内容。
const int ttsEventResponse = 352;

/// 事件：连接已建立。
const int ttsEventConnectionStarted = 50;

/// 事件：连接失败。
const int ttsEventConnectionFailed = 51;

/// 事件：连接结束。
const int ttsEventConnectionFinished = 52;

/// 不携带 session_id 的事件。
const Set<int> _noSessionEvents = <int>{1, 2, 50, 51, 52};

/// 携带 connect_id 的事件。
const Set<int> _withConnectEvents = <int>{50, 51, 52};

/// 携带 sequence / error_code 等前置字段的消息类型。
bool _isDataMessage(int messageType) =>
    messageType == ttsMsgFullClientRequest ||
    messageType == ttsMsgFullServerResponse ||
    messageType == ttsMsgAudioOnlyServer ||
    messageType == 0x0C;

/// 一帧解码后的协议数据。
class TtsFrame {
  const TtsFrame({
    required this.messageType,
    required this.flag,
    required this.serialization,
    required this.compression,
    this.event,
    this.sessionId = '',
    this.connectId = '',
    this.sequence,
    this.errorCode,
    this.payload = const <int>[],
  });

  /// 消息类型。
  final int messageType;

  /// 消息 flags。
  final int flag;

  /// 序列化方式。
  final int serialization;

  /// 压缩方式。
  final int compression;

  /// 事件码；未携带时为 `null`。
  final int? event;

  /// 会话 id；未携带时为空串。
  final String sessionId;

  /// 连接 id；仅连接类事件携带。
  final String connectId;

  /// sequence；未携带时为 `null`。
  final int? sequence;

  /// 错误码；错误帧携带。
  final int? errorCode;

  /// 已解压的负载。
  final List<int> payload;

  /// 是否为错误帧。
  bool get isError => messageType == ttsMsgError;

  /// 是否携带音频负载。
  bool get isAudio =>
      messageType == ttsMsgAudioOnlyServer || event == ttsEventResponse;

  /// 是否为会话结束。
  bool get isFinished => event == ttsEventSessionFinished;

  /// 负载按 JSON 解析；非 JSON 或解析失败返回 `null`。
  Map<String, dynamic>? get json {
    if (payload.isEmpty) return null;
    try {
      final Object? decoded = jsonDecode(utf8.decode(payload));
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  @override
  String toString() =>
      'TtsFrame(type=$messageType, event=$event, payload=${payload.length}B)';
}

/// 编码一帧。[payload] 按给定 [compression] 是否 gzip 由调用方决定：
/// 本函数按传入的 [compression] 压缩 [payload]（gzip 时）。
Uint8List buildTtsFrame({
  required int messageType,
  required int flag,
  int serialization = ttsSerializationJson,
  int compression = ttsCompressionNone,
  int? event,
  String sessionId = '',
  String connectId = '',
  int? sequence,
  int? errorCode,
  List<int> payload = const <int>[],
}) {
  final List<int> effective =
      compression == ttsCompressionGzip ? gzip.encode(payload) : payload;
  final List<int> body = <int>[];
  final ByteData scratch = ByteData(4);

  void writeInt32(int value) {
    scratch.setInt32(0, value);
    body.addAll(scratch.buffer.asUint8List());
  }

  void writeUint32(int value) {
    scratch.setUint32(0, value);
    body.addAll(scratch.buffer.asUint8List());
  }

  void writeBytes(List<int> bytes) {
    body.addAll(bytes);
  }

  if (_isDataMessage(messageType) &&
      (flag == ttsFlagPositiveSeq || flag == ttsFlagNegativeSeq)) {
    writeInt32(sequence ?? 0);
  } else if (messageType == ttsMsgError) {
    writeUint32(errorCode ?? 0);
  }

  if (flag == ttsFlagWithEvent) {
    final int resolvedEvent = event ?? 0;
    writeInt32(resolvedEvent);
    if (!_noSessionEvents.contains(resolvedEvent)) {
      final List<int> id = utf8.encode(sessionId);
      writeUint32(id.length);
      writeBytes(id);
    }
    if (_withConnectEvents.contains(resolvedEvent)) {
      final List<int> id = utf8.encode(connectId);
      writeUint32(id.length);
      writeBytes(id);
    }
  }

  writeUint32(effective.length);
  writeBytes(effective);

  final Uint8List frame = Uint8List(4 + body.length);
  frame[0] = (ttsProtocolVersion << 4) | ttsHeaderSize;
  frame[1] = (messageType << 4) | flag;
  frame[2] = (serialization << 4) | compression;
  frame[3] = 0x00;
  frame.setRange(4, 4 + body.length, body);
  return frame;
}

/// 编码一次性合成请求（full client request，gzip JSON 负载）。
Uint8List buildTtsRequest(
  Map<String, Object?> request, {
  bool compress = true,
}) =>
    buildTtsFrame(
      messageType: ttsMsgFullClientRequest,
      flag: ttsFlagNoSeq,
      compression: compress ? ttsCompressionGzip : ttsCompressionNone,
      payload: utf8.encode(jsonEncode(request)),
    );

/// 解码一帧（按 compression 自动解压负载）。结构非法时抛 [TtsException]。
TtsFrame decodeTtsFrame(List<int> bytes) {
  final Uint8List buffer =
      bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
  if (buffer.length < 4) {
    throw TtsException('TTS 帧过短：${buffer.length} 字节');
  }
  final int version = buffer[0] >> 4;
  final int headerSize = (buffer[0] & 0x0F) * 4;
  final int messageType = buffer[1] >> 4;
  final int flag = buffer[1] & 0x0F;
  final int serialization = buffer[2] >> 4;
  final int compression = buffer[2] & 0x0F;
  if (version != ttsProtocolVersion) {
    throw TtsException('不支持的 TTS 协议版本：$version');
  }
  if (headerSize < 4 || buffer.length < headerSize) {
    throw TtsException('TTS 帧头不完整：${buffer.length} 字节');
  }

  final ByteData view =
      ByteData.view(buffer.buffer, buffer.offsetInBytes, buffer.length);
  int offset = headerSize;

  void require(int need) {
    if (offset + need > buffer.length) {
      throw const TtsException('TTS 帧字段不完整');
    }
  }

  int? sequence;
  int? errorCode;
  if (_isDataMessage(messageType) &&
      (flag == ttsFlagPositiveSeq || flag == ttsFlagNegativeSeq)) {
    require(4);
    sequence = view.getInt32(offset);
    offset += 4;
  } else if (messageType == ttsMsgError) {
    require(4);
    errorCode = view.getUint32(offset);
    offset += 4;
  }

  int? event;
  String sessionId = '';
  String connectId = '';
  if (flag == ttsFlagWithEvent) {
    require(4);
    event = view.getInt32(offset);
    offset += 4;
    if (!_noSessionEvents.contains(event)) {
      require(4);
      final int length = view.getUint32(offset);
      offset += 4;
      require(length);
      sessionId =
          utf8.decode(Uint8List.sublistView(buffer, offset, offset + length));
      offset += length;
    }
    if (_withConnectEvents.contains(event)) {
      require(4);
      final int length = view.getUint32(offset);
      offset += 4;
      require(length);
      connectId =
          utf8.decode(Uint8List.sublistView(buffer, offset, offset + length));
      offset += length;
    }
  }

  require(4);
  final int payloadSize = view.getUint32(offset);
  offset += 4;
  require(payloadSize);
  final List<int> raw =
      Uint8List.sublistView(buffer, offset, offset + payloadSize);
  final List<int> payload =
      compression == ttsCompressionGzip ? gzip.decode(raw) : raw;
  return TtsFrame(
    messageType: messageType,
    flag: flag,
    serialization: serialization,
    compression: compression,
    event: event,
    sessionId: sessionId,
    connectId: connectId,
    sequence: sequence,
    errorCode: errorCode,
    payload: payload,
  );
}
