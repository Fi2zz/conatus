/// 豆包 / 火山引擎大模型语音合成 provider（v3 WebSocket 单向流式）。
///
/// 建连后发送一帧 full client request（gzip JSON：`user` + `req_params`，含文本、
/// 音色与音频参数），服务端以音频帧流式返回；收到 `SessionFinished` 事件即完成。
/// 音频帧负载直接写入 [TtsAudioSink]。协议帧由 `tts_protocol.dart` 编解码。
///
/// 鉴权通过建连 HTTP 头完成：新版控制台用 [apiKey]（`X-Api-Key`）；旧版控制台用
/// [appKey]（`X-Api-App-Key`）+ [accessToken]（`X-Api-Access-Key`）。
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'tts_audio_sink.dart';
import 'tts_protocol.dart';
import 'tts_types.dart';

/// 火山 v3 WebSocket 单向流式合成端点。
const String defaultDoubaoTtsStreamUrl =
    'wss://openspeech.bytedance.com/api/v3/tts/unidirectional/stream';

/// 默认资源 ID（豆包语音合成模型 2.0）。
const String defaultDoubaoTtsResourceId = 'seed-tts-2.0';

/// 默认音色（豆包语音合成模型 2.0）。
const String defaultDoubaoTtsVoice = 'zh_female_vv_uranus_bigtts';

/// 供 provider 使用的最小 WebSocket 抽象，便于测试替换。
abstract class TtsSocket {
  /// 入站消息（二进制为 `List<int>`）。
  Stream<Object?> get messages;

  /// 发送一帧二进制数据。
  void send(List<int> data);

  /// 关闭连接。
  Future<void> close();
}

/// 建立 [TtsSocket] 的连接器。
typedef TtsSocketConnector = Future<TtsSocket> Function(
  Uri url,
  Map<String, String> headers,
);

/// 豆包 / 火山大模型语音合成 provider（WebSocket 单向流式）。
///
/// 环境变量：`VOLC_TTS_API_KEY`（新版控制台）或 `VOLC_TTS_APP_KEY` +
/// `VOLC_TTS_ACCESS_TOKEN`（旧版控制台）、`VOLC_TTS_RESOURCE_ID`、
/// `VOLC_TTS_VOICE`。
class DoubaoStreamingTtsProvider implements TtsProvider {
  DoubaoStreamingTtsProvider({
    String? apiKey,
    String? appKey,
    String? accessToken,
    String? resourceId,
    String? voice,
    this.url = defaultDoubaoTtsStreamUrl,
    this.audioFormat = const TtsAudioFormat(format: 'pcm'),
    this.speed = 0,
    this.volume = 0,
    this.compress = true,
    this.connectTimeout = const Duration(seconds: 15),
    this.finishTimeout = const Duration(seconds: 60),
    TtsSocketConnector? connector,
  })  : apiKey = apiKey ?? _env('VOLC_TTS_API_KEY'),
        appKey = appKey ?? _env('VOLC_TTS_APP_KEY'),
        accessToken = accessToken ?? _env('VOLC_TTS_ACCESS_TOKEN'),
        resourceId = resourceId ??
            _envOr('VOLC_TTS_RESOURCE_ID', defaultDoubaoTtsResourceId),
        voice = voice ?? _envOr('VOLC_TTS_VOICE', defaultDoubaoTtsVoice),
        _connector = connector ?? _connectIo;

  /// 新版控制台 API Key。
  final String apiKey;

  /// 旧版控制台 App ID。
  final String appKey;

  /// 旧版控制台 Access Token。
  final String accessToken;

  /// 资源 ID。
  final String resourceId;

  /// 默认音色 ID。
  final String voice;

  /// 合成端点。
  final String url;

  /// 默认音频格式（流式建议 pcm）。
  @override
  final TtsAudioFormat audioFormat;

  /// 默认语速（`speech_rate`，0 为原速，范围 -50~100）。
  final double speed;

  /// 默认音量（`loudness_rate`，0 为原量，范围 -50~100）。
  final double volume;

  /// 是否 gzip 压缩请求负载。
  final bool compress;

  /// 建连超时。
  final Duration connectTimeout;

  /// 等待合成完成的超时。
  final Duration finishTimeout;

  final TtsSocketConnector _connector;

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
    final TtsSocket socket;
    try {
      socket = await _connector(Uri.parse(url), _headers()).timeout(
        connectTimeout,
      );
    } on TimeoutException {
      throw const TtsException('TTS 建连超时');
    } on SocketException catch (error) {
      throw TtsException('TTS 网络错误：${error.message}');
    }
    final _DoubaoStreamingTtsSession session = _DoubaoStreamingTtsSession(
      socket,
      sink,
      speaker: voice?.id ?? this.voice,
      format: format ?? audioFormat,
      speed: speed ?? this.speed,
      volume: volume ?? this.volume,
      compress: compress,
      timeout: finishTimeout,
    );
    await session.open();
    return session;
  }

  void _requireCredentials() {
    final bool hasApiKey = apiKey.isNotEmpty;
    final bool hasLegacy = appKey.isNotEmpty && accessToken.isNotEmpty;
    if (!hasApiKey && !hasLegacy) {
      throw const TtsException(
        '缺少火山 TTS 凭据：请设置 VOLC_TTS_API_KEY（新版控制台），'
        '或同时设置 VOLC_TTS_APP_KEY 与 VOLC_TTS_ACCESS_TOKEN（旧版控制台）',
      );
    }
  }

  Map<String, String> _headers() => <String, String>{
        'X-Api-Resource-Id': resourceId,
        'X-Api-Connect-Id': _uuid(),
        if (apiKey.isNotEmpty) 'X-Api-Key': apiKey,
        if (appKey.isNotEmpty) 'X-Api-App-Key': appKey,
        if (accessToken.isNotEmpty) 'X-Api-Access-Key': accessToken,
      };
}

/// `dart:io` WebSocket 的连接器。
Future<TtsSocket> _connectIo(Uri url, Map<String, String> headers) async {
  final WebSocket socket =
      await WebSocket.connect(url.toString(), headers: headers);
  return _IoTtsSocket(socket);
}

/// [TtsSocket] 的 `dart:io` 实现。
class _IoTtsSocket implements TtsSocket {
  _IoTtsSocket(this._socket);

  final WebSocket _socket;

  @override
  Stream<Object?> get messages => _socket;

  @override
  void send(List<int> data) => _socket.add(data);

  @override
  Future<void> close() => _socket.close();
}

/// 一次 v3 单向流式合成会话。
class _DoubaoStreamingTtsSession implements TtsSession {
  _DoubaoStreamingTtsSession(
    this._socket,
    this._sink, {
    required String speaker,
    required TtsAudioFormat format,
    required double speed,
    required double volume,
    required bool compress,
    required Duration timeout,
  })  : _speaker = speaker,
        _format = format,
        _speed = speed,
        _volume = volume,
        _compress = compress,
        _timeout = timeout;

  final TtsSocket _socket;
  final TtsAudioSink _sink;
  final String _speaker;
  final TtsAudioFormat _format;
  final double _speed;
  final double _volume;
  final bool _compress;
  final Duration _timeout;

  final StringBuffer _text = StringBuffer();
  final Completer<void> _done = Completer<void>();
  StreamSubscription<Object?>? _subscription;
  bool _closed = false;

  /// 开始监听服务端响应。
  Future<void> open() async {
    _subscription = _socket.messages.listen(
      _onMessage,
      onError: (Object error) => unawaited(_fail('$error')),
      onDone: () => unawaited(_finishAll()),
      cancelOnError: false,
    );
  }

  @override
  void send(String text) {
    if (_closed) return;
    _text.write(text);
  }

  @override
  Future<void> finish() async {
    if (_closed) return _done.future;
    final String text = _text.toString();
    if (text.trim().isEmpty) {
      await _finishAll();
      return;
    }
    _socket.send(buildTtsRequest(_request(text), compress: _compress));
    return _done.future.timeout(
      _timeout,
      onTimeout: () {
        close();
        throw const TtsException('TTS 合成超时');
      },
    );
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    if (!_done.isCompleted) _done.complete();
    unawaited(_teardown());
  }

  Map<String, Object?> _request(String text) {
    final Map<String, Object?> audio = <String, Object?>{
      'format': _format.format,
      'sample_rate': _format.rate,
      'enable_timestamp': false,
      if (_speed != 0) 'speech_rate': _speed,
      if (_volume != 0) 'loudness_rate': _volume,
    };
    return <String, Object?>{
      'user': <String, Object?>{'uid': _uuid()},
      'req_params': <String, Object?>{
        'text': text,
        'speaker': _speaker,
        'audio_params': audio,
      },
    };
  }

  void _onMessage(Object? message) {
    if (_closed || message is! List<int>) return;
    final TtsFrame frame;
    try {
      frame = decodeTtsFrame(message);
    } on TtsException catch (error) {
      unawaited(_fail(error.message));
      return;
    }
    if (frame.isError) {
      unawaited(_fail(_errorText(frame)));
      return;
    }
    if (frame.isAudio && frame.payload.isNotEmpty) {
      _sink.write(frame.payload);
    }
    if (frame.isFinished) {
      unawaited(_finishAll());
    }
  }

  String _errorText(TtsFrame frame) {
    final Object? message = frame.json?['message'];
    final String code = frame.errorCode?.toString() ?? '?';
    if (message is String && message.isNotEmpty) {
      return 'TTS 服务错误 $code：$message';
    }
    return 'TTS 服务错误 $code（payload ${frame.payload.length} 字节）';
  }

  Future<void> _finishAll() async {
    if (_closed) return;
    _closed = true;
    await _teardown();
    if (!_done.isCompleted) _done.complete();
  }

  Future<void> _fail(String message) async {
    if (_closed) return;
    _closed = true;
    await _teardown();
    if (!_done.isCompleted) _done.completeError(TtsException(message));
  }

  Future<void> _teardown() async {
    await _subscription?.cancel();
    await _socket.close();
    await _sink.close();
  }
}

String _env(String key) => Platform.environment[key] ?? '';

String _envOr(String key, String fallback) {
  final String value = _env(key);
  return value.isEmpty ? fallback : value;
}

/// 生成随机 UUID v4。
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
