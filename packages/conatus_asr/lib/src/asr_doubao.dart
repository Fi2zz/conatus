/// 豆包 / 火山引擎大模型流式语音识别 provider（SAUC 双向流式 WebSocket）。
///
/// 建连后先发 full client request（JSON 元数据），再持续发 audio-only 帧，最后一帧
/// 以负 sequence 标记；服务端以 full server response 返回增量与最终文本。协议帧由
/// `asr_protocol.dart` 编解码。
///
/// 鉴权通过建连 HTTP 头完成：新版控制台只需 [apiKey]（`X-Api-Key`）；旧版控制台用
/// [appKey]（`X-Api-App-Key`）+ [accessKey]（`X-Api-Access-Key`）。二者可只配其一。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'asr_protocol.dart';
import 'asr_types.dart';

/// 火山 SAUC 双向流式端点。
const String defaultDoubaoAsrUrl =
    'wss://openspeech.bytedance.com/api/v3/sauc/bigmodel';

/// 豆包流式语音识别模型 1.0（小时版）资源 ID。
const String doubaoAsrResourceDuration = 'volc.bigasr.sauc.duration';

/// 豆包流式语音识别模型 2.0（小时版）资源 ID。
const String doubaoAsrResourceSeedDuration = 'volc.seedasr.sauc.duration';

/// 供 provider 使用的最小 WebSocket 抽象，便于测试替换。
abstract class AsrSocket {
  /// 入站消息（二进制为 `List<int>`）。
  Stream<Object?> get messages;

  /// 发送一帧二进制数据。
  void send(List<int> data);

  /// 关闭连接。
  Future<void> close();
}

/// 建立 [AsrSocket] 的连接器。
typedef AsrSocketConnector = Future<AsrSocket> Function(
  Uri url,
  Map<String, String> headers,
);

/// 动态解析鉴权头（如向后端换取短时签名 / 令牌）。
///
/// 返回值与默认头合并（同名覆盖），因此可在此注入 HMAC 签名、临时 token 等，
/// 避免把长期密钥写进客户端（Flutter 场景尤其重要）。
typedef DoubaoAuthHeaders = FutureOr<Map<String, String>> Function();

/// 豆包 / 火山大模型流式语音识别 provider。
///
/// 鉴权头来源（优先级从高到低）：
/// 1. [auth] 回调动态产出（签名 / 短时令牌）；
/// 2. 构造参数或环境变量给出的静态凭据。
///
/// 环境变量：`VOLC_ASR_API_KEY` / `VOLC_ASR_APP_KEY` / `VOLC_ASR_ACCESS_KEY` /
/// `VOLC_ASR_RESOURCE_ID`。
class DoubaoStreamingAsrProvider implements AsrProvider {
  DoubaoStreamingAsrProvider({
    String? apiKey,
    String? appKey,
    String? accessKey,
    String? resourceId,
    this.url = defaultDoubaoAsrUrl,
    this.audioFormat = const AsrAudioFormat(),
    this.compress = false,
    this.connectTimeout = const Duration(seconds: 15),
    this.finalTimeout = const Duration(seconds: 20),
    this.auth,
    AsrSocketConnector? connector,
  })  : apiKey = apiKey ?? _env('VOLC_ASR_API_KEY'),
        appKey = appKey ?? _env('VOLC_ASR_APP_KEY'),
        accessKey = accessKey ?? _env('VOLC_ASR_ACCESS_KEY'),
        resourceId = resourceId ??
            _envOr('VOLC_ASR_RESOURCE_ID', doubaoAsrResourceDuration),
        _connector = connector ?? _connectIo;

  /// 新版控制台 API Key。
  final String apiKey;

  /// 旧版控制台 App ID。
  final String appKey;

  /// 旧版控制台 Access Token。
  final String accessKey;

  /// 资源 ID。
  final String resourceId;

  /// 建连地址。
  final String url;

  /// 默认音频参数。
  @override
  final AsrAudioFormat audioFormat;

  /// 是否 gzip 压缩帧负载（服务端镜像客户端的选择）。
  final bool compress;

  /// 建连超时。
  final Duration connectTimeout;

  /// 等待最终结果的超时。
  final Duration finalTimeout;

  /// 动态鉴权头回调；非空时其返回值覆盖默认静态凭据头。
  final DoubaoAuthHeaders? auth;

  final AsrSocketConnector _connector;

  @override
  String get name => 'doubao';

  @override
  Future<AsrSession> start({
    AsrAudioFormat? audio,
    String? language,
    List<String> hotwords = const <String>[],
  }) async {
    _requireCredentials();
    final Map<String, String> headers = await _resolveHeaders();
    final AsrSocket socket;
    try {
      socket = await _connector(Uri.parse(url), headers).timeout(
        connectTimeout,
      );
    } on TimeoutException {
      throw const AsrException('ASR 建连超时');
    } on SocketException catch (error) {
      throw AsrException('ASR 网络错误：${error.message}');
    }
    final _DoubaoAsrSession session = _DoubaoAsrSession(
      socket,
      format: audio ?? audioFormat,
      compress: compress,
      language: language,
      hotwords: hotwords,
      finalTimeout: finalTimeout,
    );
    await session.open();
    return session;
  }

  void _requireCredentials() {
    if (auth != null) return;
    final bool hasApiKey = apiKey.isNotEmpty;
    final bool hasLegacy = appKey.isNotEmpty && accessKey.isNotEmpty;
    if (!hasApiKey && !hasLegacy) {
      throw const AsrException(
        '缺少火山 ASR 凭据：请设置 VOLC_ASR_API_KEY（新版控制台），'
        '或同时设置 VOLC_ASR_APP_KEY 与 VOLC_ASR_ACCESS_KEY（旧版控制台），'
        '或传入 auth 回调动态产出鉴权头',
      );
    }
  }

  /// 合并默认头与 [auth] 返回的动态头（后者覆盖同名）。
  Future<Map<String, String>> _resolveHeaders() async {
    final Map<String, String> headers = _baseHeaders();
    final DoubaoAuthHeaders? auth = this.auth;
    if (auth != null) {
      headers.addAll(await auth());
    }
    return headers;
  }

  Map<String, String> _baseHeaders() => <String, String>{
        'X-Api-Resource-Id': resourceId,
        'X-Api-Connect-Id': _uuid(),
        'X-Api-Request-Id': _uuid(),
        'X-Api-Sequence': '-1',
        if (apiKey.isNotEmpty) 'X-Api-Key': apiKey,
        if (appKey.isNotEmpty) 'X-Api-App-Key': appKey,
        if (accessKey.isNotEmpty) 'X-Api-Access-Key': accessKey,
      };
}

/// `dart:io` WebSocket 的连接器。
Future<AsrSocket> _connectIo(Uri url, Map<String, String> headers) async {
  final WebSocket socket =
      await WebSocket.connect(url.toString(), headers: headers);
  return _IoAsrSocket(socket);
}

/// [AsrSocket] 的 `dart:io` 实现。
class _IoAsrSocket implements AsrSocket {
  _IoAsrSocket(this._socket);

  final WebSocket _socket;

  @override
  Stream<Object?> get messages => _socket;

  @override
  void send(List<int> data) => _socket.add(data);

  @override
  Future<void> close() => _socket.close();
}

/// 一次豆包流式识别会话。
class _DoubaoAsrSession implements AsrSession {
  _DoubaoAsrSession(
    this._socket, {
    required AsrAudioFormat format,
    required bool compress,
    required String? language,
    required List<String> hotwords,
    required Duration finalTimeout,
  })  : _format = format,
        _compress = compress,
        _language = language,
        _hotwords = hotwords,
        _finalTimeout = finalTimeout;

  final AsrSocket _socket;
  final AsrAudioFormat _format;
  final bool _compress;
  final String? _language;
  final List<String> _hotwords;
  final Duration _finalTimeout;

  final StreamController<AsrEvent> _events = StreamController<AsrEvent>();
  final Completer<void> _done = Completer<void>();
  StreamSubscription<Object?>? _subscription;
  int _sequence = 0;
  bool _finished = false;
  bool _closed = false;

  @override
  Stream<AsrEvent> get events => _events.stream;

  /// 发送 full client request 并开始监听服务端响应。
  Future<void> open() async {
    _subscription = _socket.messages.listen(
      _onMessage,
      onError: _onError,
      onDone: _onDone,
      cancelOnError: false,
    );
    _socket.send(buildFullClientRequest(_startRequest(), compress: _compress));
  }

  Map<String, Object?> _startRequest() {
    final Map<String, Object?> audio = _format.toJson();
    if (_language != null && _language.isNotEmpty) {
      audio['language'] = _language;
    }
    final Map<String, Object?> request = <String, Object?>{
      'model_name': 'bigmodel',
    };
    if (_hotwords.isNotEmpty) {
      request['corpus'] = <String, Object?>{
        'context': jsonEncode(<String, Object?>{
          'context_type': 'dialog_ctx',
          'context_data': <Map<String, Object?>>[
            for (final String word in _hotwords)
              <String, Object?>{'word': word},
          ],
        }),
      };
    }
    return <String, Object?>{
      'user': <String, Object?>{
        'uid': 'conatus',
        'platform': Platform.operatingSystem,
      },
      'audio': audio,
      'request': request,
    };
  }

  @override
  void send(List<int> bytes) {
    if (_closed || _finished) return;
    _socket.send(
      buildAudioFrame(
        bytes,
        sequence: ++_sequence,
        compress: _compress,
      ),
    );
  }

  @override
  Future<void> finish() {
    if (_finished || _closed) return _done.future;
    _finished = true;
    _socket.send(
      buildAudioFrame(
        const <int>[],
        sequence: _sequence + 1,
        last: true,
        compress: _compress,
      ),
    );
    return _done.future.timeout(
      _finalTimeout,
      onTimeout: () {
        close();
        throw const AsrException('ASR 等待最终结果超时');
      },
    );
  }

  @override
  void close() {
    if (_closed) return;
    if (!_done.isCompleted) _done.complete();
    _teardown();
  }

  void _onMessage(Object? message) {
    if (message is! List<int>) return;
    final AsrFrame frame;
    try {
      frame = decodeAsrFrame(message);
    } on AsrException catch (error) {
      _fail(error.message);
      return;
    }
    if (frame.isError) {
      _fail(_errorText(frame));
      return;
    }
    final Map<String, dynamic>? json = decodeAsrJson(frame);
    if (json == null) return;
    final AsrResult result = _parseResult(json, isFinal: frame.isLast);
    if (frame.isLast) {
      _emit(AsrFinal(result));
      _complete();
    } else {
      _emit(AsrPartial(result));
    }
  }

  AsrResult _parseResult(Map<String, dynamic> json, {required bool isFinal}) {
    final Map<String, dynamic> result =
        (json['result'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final String text = (result['text'] as String?) ?? '';
    final List<AsrUtterance> utterances = <AsrUtterance>[];
    final Object? raw = result['utterances'];
    if (raw is List) {
      for (final Object? item in raw) {
        if (item is! Map) continue;
        final Object? itemText = item['text'];
        if (itemText is! String) continue;
        utterances.add(AsrUtterance(
          text: itemText,
          startMs: item['start_time'] is int ? item['start_time'] as int : null,
          endMs: item['end_time'] is int ? item['end_time'] as int : null,
          definite: item['definite'] == true,
        ));
      }
    }
    return AsrResult(text: text, utterances: utterances, isFinal: isFinal);
  }

  String _errorText(AsrFrame frame) {
    final Map<String, dynamic>? json = decodeAsrJson(frame);
    final Object? message = json?['message'];
    if (message is String && message.isNotEmpty) return message;
    return 'ASR 服务返回错误（${frame.payload.length} 字节）：${json?['error']}';
  }

  void _emit(AsrEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  void _complete() {
    if (!_done.isCompleted) _done.complete();
    _teardown();
  }

  void _fail(String message) {
    final AsrException error = AsrException(message);
    if (!_events.isClosed) _events.addError(error);
    if (!_done.isCompleted) _done.completeError(error);
    _teardown();
  }

  void _onError(Object error) => _fail('$error');

  void _onDone() {
    if (!_done.isCompleted) _done.complete();
    _teardown();
  }

  void _teardown() {
    if (_closed) return;
    _closed = true;
    unawaited(_subscription?.cancel() ?? Future<void>.value());
    unawaited(_events.close());
    unawaited(_socket.close());
  }
}

String _env(String key) => Platform.environment[key] ?? '';

String _envOr(String key, String fallback) {
  final String value = _env(key);
  return value.isEmpty ? fallback : value;
}

/// 生成随机的 UUID v4（用于 `X-Api-Connect-Id` / `X-Api-Request-Id`）。
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
