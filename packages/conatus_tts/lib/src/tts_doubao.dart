/// 豆包 / 火山引擎语音合成 provider（HTTP `query` 一次性合成，返回 base64 音频）。
///
/// 请求体携带 `app`（appid / token / cluster）、`audio`（voice_type / encoding /
/// 语速等）与 `request`（text / operation），响应 `data` 为 base64 编码的音频，
/// 解码后写入 [TtsAudioSink]。
///
/// 鉴权通过请求体的 `app.appid` / `app.token` 完成。环境变量：
/// `VOLC_TTS_APP_ID` / `VOLC_TTS_ACCESS_TOKEN` / `VOLC_TTS_CLUSTER` /
/// `VOLC_TTS_VOICE`。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'tts_audio_sink.dart';
import 'tts_types.dart';

/// 火山语音合成 HTTP 端点。
const String defaultDoubaoHttpTtsUrl =
    'https://openspeech.bytedance.com/api/v1/tts';

/// 默认业务集群。
const String defaultDoubaoTtsCluster = 'volcano_tts';

/// 默认音色。
const String defaultDoubaoTtsVoice = 'zh_female_cancan_mars_bigtts';

/// 每次写入 sink 的音频分片字节数。
const int _ttsChunkBytes = 8192;

/// 豆包 / 火山语音合成 provider（HTTP 一次性合成）。
class DoubaoHttpTtsProvider implements TtsProvider {
  DoubaoHttpTtsProvider({
    String? appId,
    String? accessToken,
    String? cluster,
    String? voice,
    this.url = defaultDoubaoHttpTtsUrl,
    this.audioFormat = const TtsAudioFormat(),
    this.speed = 1.0,
    this.volume = 1.0,
    this.pitch = 1.0,
    this.timeout = const Duration(seconds: 30),
    http.Client? client,
  })  : appId = appId ?? _env('VOLC_TTS_APP_ID'),
        accessToken = accessToken ?? _env('VOLC_TTS_ACCESS_TOKEN'),
        cluster =
            cluster ?? _envOr('VOLC_TTS_CLUSTER', defaultDoubaoTtsCluster),
        voice = voice ?? _envOr('VOLC_TTS_VOICE', defaultDoubaoTtsVoice),
        _client = client ?? http.Client();

  /// 应用 App ID。
  final String appId;

  /// 访问令牌。
  final String accessToken;

  /// 业务集群。
  final String cluster;

  /// 默认音色 ID。
  final String voice;

  /// 合成端点。
  final String url;

  /// 默认音频格式。
  @override
  final TtsAudioFormat audioFormat;

  /// 默认语速（1.0 为原速）。
  final double speed;

  /// 默认音量（1.0 为原量）。
  final double volume;

  /// 默认音高（1.0 为原调）。
  final double pitch;

  /// 请求超时。
  final Duration timeout;

  final http.Client _client;

  @override
  String get name => 'doubao';

  @override
  TtsVoice? get defaultVoice => TtsVoice(voice);

  @override
  Future<TtsSession> start(
    TtsAudioSink sink, {
    TtsVoice? voice,
    TtsAudioFormat? format,
    double? speed,
    double? volume,
    double? pitch,
  }) async {
    _requireCredentials();
    return _DoubaoHttpTtsSession(
      this,
      sink,
      voice: voice ?? TtsVoice(this.voice),
      format: format ?? audioFormat,
      speed: speed ?? this.speed,
      volume: volume ?? this.volume,
      pitch: pitch ?? this.pitch,
    );
  }

  void _requireCredentials() {
    if (appId.isEmpty || accessToken.isEmpty) {
      throw const TtsException(
        '缺少火山 TTS 凭据：请设置 VOLC_TTS_APP_ID 与 VOLC_TTS_ACCESS_TOKEN，'
        '或在构造 / provideTts 时显式传入',
      );
    }
  }

  /// 请求一次合成并返回解码后的音频字节。
  Future<List<int>> _synthesize(
    String text, {
    required TtsVoice voice,
    required TtsAudioFormat format,
    required double speed,
    required double volume,
    required double pitch,
  }) async {
    _requireCredentials();
    final Map<String, Object?> body = <String, Object?>{
      'app': <String, Object?>{
        'appid': appId,
        'token': accessToken,
        'cluster': cluster,
      },
      'user': <String, Object?>{'uid': appId},
      'audio': <String, Object?>{
        'voice_type': voice.id,
        'encoding': format.format,
        'speed_ratio': speed,
        'volume_ratio': volume,
        'pitch_ratio': pitch,
      },
      'request': <String, Object?>{
        'reqid': _uuid(),
        'text': text,
        'text_type': 'plain',
        'operation': 'query',
      },
    };

    final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse(url),
            headers: <String, String>{'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw TtsException('TTS 请求超时（${timeout.inSeconds}s）');
    } on SocketException catch (error) {
      throw TtsException('TTS 网络错误：${error.message}');
    }
    if (response.statusCode != 200) {
      throw TtsException('TTS HTTP ${response.statusCode}：${response.body}');
    }

    final Object? decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw const TtsException('TTS 响应不是合法 JSON 对象');
    }
    final Object? code = decoded['code'];
    if (code != 3000) {
      throw TtsException('火山 TTS 错误 $code：${decoded['message']}');
    }
    final Object? data = decoded['data'];
    if (data is! String || data.isEmpty) {
      throw const TtsException('火山 TTS 未返回音频数据');
    }
    return base64Decode(data);
  }
}

/// 一次 HTTP 合成会话：累积文本，[finish] 时请求并把音频写入 sink。
class _DoubaoHttpTtsSession implements TtsSession {
  _DoubaoHttpTtsSession(
    this._provider,
    this._sink, {
    required this.voice,
    required this.format,
    required this.speed,
    required this.volume,
    required this.pitch,
  });

  final DoubaoHttpTtsProvider _provider;
  final TtsAudioSink _sink;
  final TtsVoice voice;
  final TtsAudioFormat format;
  final double speed;
  final double volume;
  final double pitch;

  final StringBuffer _text = StringBuffer();
  bool _closed = false;

  @override
  void send(String text) {
    if (_closed) return;
    _text.write(text);
  }

  @override
  Future<void> finish() async {
    if (_closed) return;
    _closed = true;
    try {
      final List<int> bytes = await _provider._synthesize(
        _text.toString(),
        voice: voice,
        format: format,
        speed: speed,
        volume: volume,
        pitch: pitch,
      );
      for (int offset = 0; offset < bytes.length; offset += _ttsChunkBytes) {
        final int end = offset + _ttsChunkBytes < bytes.length
            ? offset + _ttsChunkBytes
            : bytes.length;
        _sink.write(bytes.sublist(offset, end));
      }
    } finally {
      await _sink.close();
    }
  }

  @override
  void close() {
    _closed = true;
  }
}

String _env(String key) => Platform.environment[key] ?? '';

String _envOr(String key, String fallback) {
  final String value = _env(key);
  return value.isEmpty ? fallback : value;
}

/// 生成随机 UUID v4（用于 `request.reqid`）。
String _uuid() {
  final Random random = Random();
  final List<int> bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0F) | 0x40;
  bytes[8] = (bytes[8] & 0x3F) | 0x80;
  String hex(int index) => bytes[index].toRadixString(16).padLeft(2, '0');
  return '${hex(0)}${hex(1)}${hex(2)}${hex(3)}-'
      '${hex(4)}${hex(5)}-'
      '${hex(6)}${hex(7)}-'
      '${hex(8)}${hex(9)}-'
      '${hex(10)}${hex(11)}${hex(12)}${hex(13)}${hex(14)}${hex(15)}';
}
