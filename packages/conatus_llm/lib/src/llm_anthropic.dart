/// Anthropic Messages wire：请求映射、认证与 SSE 解析。
///
/// 端点固定为 `{baseUrl}/messages`；支持文本、图片、工具调用与工具结果。
/// 认证按主机区分：`opencode.ai` 用 `Authorization: Bearer`（Console 的
/// `ANTHROPIC_AUTH_TOKEN` 走法），其它主机用 `x-api-key`（Anthropic 原生）。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:conatus_credentials/conatus_credentials.dart';
import 'package:http/http.dart' as http;

import 'llm.dart';
import 'llm_openai.dart' show kDefaultLlmUserAgent, parseRetryAfter;
import 'llm_retry.dart';

/// Anthropic Messages 提供商。
class AnthropicProvider implements LlmProvider {
  AnthropicProvider({
    required this.name,
    required String baseUrl,
    required this.model,
    this.credentialKey = '',
    String? apiKey,
    this.userAgent = kDefaultLlmUserAgent,
    this.headersProvider,
    this.defaultMaxTokens = 4096,
    http.Client? client,
    Credentials? credentials,
    this.timeout = const Duration(seconds: 60),
  })  : baseUrl = _normalize(baseUrl),
        apiKey = _resolveApiKey(apiKey, credentials, credentialKey),
        _client = client ?? http.Client() {
    _watchCredentials(credentials);
  }

  /// 展示名（如 `'opencode-go-anthropic'`）。
  @override
  final String name;

  /// 端点根地址（如 `https://api.anthropic.com/v1`）。
  final String baseUrl;
  final String model;
  final String credentialKey;
  final String userAgent;

  /// 每次请求时重算的附加头（如 `x-opencode-session`）。
  final Map<String, String> Function()? headersProvider;

  /// `max_tokens` 缺省值（Anthropic 必填）。
  final int defaultMaxTokens;
  final Duration timeout;

  /// 当前 API Key；凭据变更时就地轮换。
  String apiKey;

  final http.Client _client;
  StreamSubscription<Credential>? _credentialsSubscription;

  static String _normalize(String baseUrl) =>
      baseUrl.replaceFirst(RegExp(r'/+$'), '');

  static String _resolveApiKey(
    String? apiKey,
    Credentials? credentials,
    String credentialKey,
  ) =>
      apiKey ?? credentials?.get(credentialKey)?.value ?? '';

  void _watchCredentials(Credentials? credentials) {
    if (credentials == null || credentialKey.isEmpty) return;
    _credentialsSubscription = credentials.changes.listen((Credential c) {
      if (c.key == credentialKey && !c.expired) apiKey = c.value;
    });
  }

  Uri get _endpoint => Uri.parse('$baseUrl/messages');

  Map<String, String> get _headers {
    final bool openCode = Uri.parse(baseUrl).host == 'opencode.ai';
    return <String, String>{
      'Content-Type': 'application/json',
      'anthropic-version': '2023-06-01',
      if (openCode) 'Authorization': 'Bearer $apiKey' else 'x-api-key': apiKey,
      'User-Agent': userAgent,
      ...?headersProvider?.call(),
    };
  }

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) =>
      streamChatResult(this, messages, options: options, tools: tools);

  @override
  Stream<LlmStreamEvent> chatStream(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async* {
    _requireKey();
    final http.Request request = http.Request('POST', _endpoint)
      ..headers.addAll(_headers)
      ..body = jsonEncode(
        _body(messages, stream: true, options: options, tools: tools),
      );

    final http.StreamedResponse response;
    try {
      response = await _client.send(request).timeout(timeout);
    } on TimeoutException {
      throw _transportFailure('请求超时（${timeout.inSeconds}s）');
    } on SocketException catch (e) {
      throw _transportFailure('网络错误：${e.message}');
    } on http.ClientException catch (e) {
      throw _transportFailure('网络错误：${e.message}');
    }

    if (response.statusCode != 200) {
      final String body = await response.stream.bytesToString();
      throw LlmException(
        name,
        _errorMessage(response.statusCode, body),
        statusCode: response.statusCode,
        retryAfter: parseRetryAfter(response.headers['retry-after']),
      );
    }

    final _AnthropicStreamState state = _AnthropicStreamState();
    await for (final String data in _sseData(response.stream)) {
      final Map<String, dynamic>? json = _tryDecode(data);
      if (json == null) continue;
      for (final LlmStreamEvent event in _frame(json, state)) {
        yield event;
      }
    }
    yield LlmStreamDone(
      provider: name,
      model: state.model.isEmpty ? model : state.model,
      usage: state.usage,
      finishReason: state.finishReason,
      toolCalls: state.buildToolCalls(),
      thinkingBlocks: state.buildThinkingBlocks(),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // 请求体
  // ═══════════════════════════════════════════════════════════════

  Map<String, dynamic> _body(
    List<LlmMessage> messages, {
    required bool stream,
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) {
    final List<String> system = <String>[];
    bool systemCacheable = false;
    final List<Map<String, dynamic>> turns = <Map<String, dynamic>>[];
    final int lastCacheable = messages.lastIndexWhere(
      (LlmMessage m) => m.cacheable && m.role != 'system',
    );
    for (final (int index, LlmMessage message) in messages.indexed) {
      switch (message.role) {
        case 'system':
          if (message.content.trim().isNotEmpty) {
            system.add(message.content);
            if (message.cacheable) systemCacheable = true;
          }
        case 'tool':
          _append(
            turns,
            'user',
            <Map<String, dynamic>>[
              <String, dynamic>{
                'type': 'tool_result',
                'tool_use_id': message.toolCallId ?? '',
                'content': _toolResultContent(message),
              },
            ],
          );
        case 'assistant':
          final List<Map<String, dynamic>> blocks = <Map<String, dynamic>>[];
          blocks.addAll(message.thinkingBlocks);
          if (message.content.isNotEmpty) {
            blocks.add(<String, dynamic>{
              'type': 'text',
              'text': message.content,
            });
          }
          for (final LlmToolCall call in message.toolCalls) {
            blocks.add(<String, dynamic>{
              'type': 'tool_use',
              'id': call.id,
              'name': call.name,
              'input': _decodeArguments(call.arguments),
            });
          }
          if (blocks.isNotEmpty) {
            if (index == lastCacheable) _markCache(blocks);
            _append(turns, 'assistant', blocks);
          }
        default:
          final List<Map<String, dynamic>> blocks = <Map<String, dynamic>>[];
          if (message.content.isNotEmpty) {
            blocks.add(<String, dynamic>{
              'type': 'text',
              'text': message.content,
            });
          }
          for (final LlmImage image in message.images) {
            blocks.add(<String, dynamic>{
              'type': 'image',
              'source': <String, String>{
                'type': 'base64',
                'media_type': image.mimeType,
                'data': image.base64Data,
              },
            });
          }
          for (final LlmFile file in message.files) {
            blocks.add(_fileBlock(file));
          }
          if (blocks.isNotEmpty) {
            if (index == lastCacheable) _markCache(blocks);
            _append(turns, 'user', blocks);
          }
      }
    }

    final Map<String, dynamic> body = <String, dynamic>{
      'model': model,
      'max_tokens': _maxTokens(options),
      'messages': turns,
      if (system.isNotEmpty)
        'system': systemCacheable
            ? <Map<String, dynamic>>[
                <String, dynamic>{
                  'type': 'text',
                  'text': system.join('\n\n'),
                  'cache_control': _ephemeral,
                },
              ]
            : system.join('\n\n'),
      if (stream) 'stream': true,
      if (tools != null && tools.isNotEmpty)
        'tools': <Map<String, dynamic>>[
          for (final (int index, Map<String, dynamic> tool) in tools.indexed)
            <String, dynamic>{
              'name': tool['name'],
              'description': tool['description'] ?? '',
              'input_schema':
                  tool['parameters'] ?? <String, dynamic>{'type': 'object'},
              if (index == tools.length - 1) 'cache_control': _ephemeral,
            },
        ],
    };
    for (final String key in const <String>[
      'temperature',
      'top_p',
      'top_k',
      'stop_sequences',
      'thinking',
    ]) {
      if (options != null && options.containsKey(key)) {
        body[key] = options[key];
      }
    }
    return body;
  }

  static const Map<String, String> _ephemeral = <String, String>{
    'type': 'ephemeral',
  };

  /// 给最后一块内容打上 prompt caching 断点。
  void _markCache(List<Map<String, dynamic>> blocks) {
    if (blocks.isEmpty) return;
    blocks.last['cache_control'] = _ephemeral;
  }

  Object _toolResultContent(LlmMessage message) {
    if (message.images.isEmpty && message.files.isEmpty) {
      return message.content;
    }
    return <Map<String, dynamic>>[
      if (message.content.isNotEmpty)
        <String, dynamic>{'type': 'text', 'text': message.content},
      for (final LlmImage image in message.images)
        <String, dynamic>{
          'type': 'image',
          'source': <String, String>{
            'type': 'base64',
            'media_type': image.mimeType,
            'data': image.base64Data,
          },
        },
      for (final LlmFile file in message.files) _fileBlock(file),
    ];
  }

  Map<String, dynamic> _fileBlock(LlmFile file) {
    if (file.mimeType == 'application/pdf') {
      return <String, dynamic>{
        'type': 'document',
        'source': <String, String>{
          'type': 'base64',
          'media_type': 'application/pdf',
          'data': file.base64Data,
        },
      };
    }
    return <String, dynamic>{
      'type': 'text',
      'text': '（附件 ${file.filename ?? file.mimeType} 暂不支持内联）',
    };
  }

  int _maxTokens(Map<String, dynamic>? options) {
    final Object? value = options?['max_tokens'];
    return value is int && value > 0 ? value : defaultMaxTokens;
  }

  /// 合并相邻同角色消息：Anthropic 的 `tool_result` 必须与后续 user 内容
  /// 同处一条消息，连续工具结果也应合并。
  void _append(
    List<Map<String, dynamic>> turns,
    String role,
    List<Map<String, dynamic>> blocks,
  ) {
    if (turns.isNotEmpty && turns.last['role'] == role) {
      (turns.last['content'] as List<dynamic>).addAll(blocks);
      return;
    }
    turns.add(<String, dynamic>{'role': role, 'content': blocks});
  }

  Map<String, dynamic> _decodeArguments(String raw) {
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
    } on FormatException {
      // 模型产出的非法 JSON 不炸会话，按空参数交给工具校验。
    }
    return <String, dynamic>{};
  }

  // ═══════════════════════════════════════════════════════════════
  // 流式事件
  // ═══════════════════════════════════════════════════════════════

  List<LlmStreamEvent> _frame(
    Map<String, dynamic> json,
    _AnthropicStreamState state,
  ) {
    switch (json['type'] as String? ?? '') {
      case 'message_start':
        final Object? message = json['message'];
        if (message is Map<String, dynamic>) {
          final Object? modelName = message['model'];
          if (modelName is String && modelName.isNotEmpty) {
            state.model = modelName;
          }
          state.mergeUsage(message['usage']);
        }
      case 'content_block_start':
        final Object? block = json['content_block'];
        if (block is Map<String, dynamic>) {
          final int index = json['index'] as int? ?? 0;
          if (block['type'] == 'thinking') {
            final String text = block['thinking'] as String? ?? '';
            if (text.isNotEmpty) state.thinking(index).addText(text);
          } else if (block['type'] == 'tool_use') {
            final _AnthropicToolBuilder builder = state.builder(index);
            builder.id = block['id'] as String? ?? builder.id;
            builder.name = block['name'] as String? ?? builder.name;
          }
        }
      case 'content_block_delta':
        final Object? delta = json['delta'];
        if (delta is Map<String, dynamic>) {
          switch (delta['type'] as String? ?? '') {
            case 'text_delta':
              final String text = delta['text'] as String? ?? '';
              if (text.isNotEmpty) return <LlmStreamEvent>[LlmTextDelta(text)];
            case 'thinking_delta':
              final String text = delta['thinking'] as String? ?? '';
              if (text.isNotEmpty) {
                state.thinking(json['index'] as int? ?? 0).addText(text);
                return <LlmStreamEvent>[LlmReasoningDelta(text)];
              }
            case 'signature_delta':
              final String signature = delta['signature'] as String? ?? '';
              if (signature.isNotEmpty) {
                state.thinking(json['index'] as int? ?? 0).signature =
                    signature;
              }
            case 'input_json_delta':
              state
                  .builder(json['index'] as int? ?? 0)
                  .add(delta['partial_json']);
          }
        }
      case 'message_delta':
        final Object? delta = json['delta'];
        if (delta is Map<String, dynamic>) {
          final Object? reason = delta['stop_reason'];
          if (reason is String) state.finishReason = reason;
        }
        state.mergeUsage(json['usage']);
      case 'error':
        final Object? error = json['error'];
        final Object? message =
            error is Map<String, dynamic> ? error['message'] : error;
        throw LlmException(
          name,
          '流式响应失败：${message ?? 'unknown'}',
          kind: LlmErrorKind.server,
        );
      default:
        return const <LlmStreamEvent>[];
    }
    return const <LlmStreamEvent>[];
  }

  void _requireKey() {
    if (apiKey.isEmpty) {
      throw LlmException(
        name,
        credentialKey.isEmpty
            ? '缺少 API Key'
            : '缺少 API Key（凭据键：$credentialKey 未配置）',
        kind: LlmErrorKind.config,
      );
    }
  }

  LlmException _transportFailure(String message) =>
      LlmException(name, message, kind: LlmErrorKind.network);

  String _errorMessage(int statusCode, String body) {
    final Map<String, dynamic>? decoded = _tryDecode(body.trim());
    if (decoded == null) {
      return body.trim().isEmpty ? 'HTTP $statusCode' : body.trim();
    }
    final Object? error = decoded['error'];
    if (error is Map && error['message'] is String) {
      return error['message']! as String;
    }
    if (decoded['message'] is String) return decoded['message']! as String;
    return body.trim().isEmpty ? 'HTTP $statusCode' : body.trim();
  }

  @override
  void close() {
    unawaited(_credentialsSubscription?.cancel());
    _credentialsSubscription = null;
    _client.close();
  }
}

/// 流式累积状态。
class _AnthropicStreamState {
  String model = '';
  String? finishReason;
  Map<String, dynamic> usage = const <String, dynamic>{};
  final Map<int, _AnthropicToolBuilder> _builders =
      <int, _AnthropicToolBuilder>{};
  final Map<int, _AnthropicThinkingBuilder> _thinking =
      <int, _AnthropicThinkingBuilder>{};

  _AnthropicToolBuilder builder(int index) =>
      _builders.putIfAbsent(index, _AnthropicToolBuilder.new);

  _AnthropicThinkingBuilder thinking(int index) =>
      _thinking.putIfAbsent(index, _AnthropicThinkingBuilder.new);

  List<Map<String, dynamic>> buildThinkingBlocks() => <Map<String, dynamic>>[
        for (final _AnthropicThinkingBuilder builder in _thinking.values)
          if (builder.build() case final Map<String, dynamic> block) block,
      ];

  void mergeUsage(Object? raw) {
    if (raw is! Map<String, dynamic>) return;
    usage = <String, dynamic>{...usage, ...raw};
    final Object? cacheRead = raw['cache_read_input_tokens'];
    if (cacheRead is int && cacheRead > 0) {
      usage['input_tokens_details'] = <String, dynamic>{
        'cached_tokens': cacheRead,
      };
    }
  }

  List<LlmToolCall> buildToolCalls() => <LlmToolCall>[
        for (final _AnthropicToolBuilder builder in _builders.values)
          builder.build(),
      ].where((LlmToolCall call) => call.name.isNotEmpty).toList();
}

class _AnthropicThinkingBuilder {
  final StringBuffer _text = StringBuffer();
  String signature = '';

  void addText(String chunk) => _text.write(chunk);

  /// signature 为空时不可回传（Anthropic 会拒绝），只在可回传时产出。
  Map<String, dynamic>? build() => signature.isEmpty
      ? null
      : <String, dynamic>{
          'type': 'thinking',
          'thinking': _text.toString(),
          'signature': signature,
        };
}

class _AnthropicToolBuilder {
  String id = '';
  String name = '';
  final StringBuffer _arguments = StringBuffer();

  void add(Object? chunk) {
    if (chunk is String && chunk.isNotEmpty) _arguments.write(chunk);
  }

  LlmToolCall build() => LlmToolCall(
        id: id,
        name: name,
        arguments: _arguments.isEmpty ? '{}' : _arguments.toString(),
      );
}

Map<String, dynamic>? _tryDecode(String data) {
  try {
    final Object? decoded = jsonDecode(data);
    return decoded is Map<String, dynamic> ? decoded : null;
  } on FormatException {
    return null;
  }
}

/// SSE `data:` 载荷流（Anthropic 与 OpenAI 的帧格式相同）。
Stream<String> _sseData(Stream<List<int>> byteStream) async* {
  final StringBuffer pending = StringBuffer();
  await for (final String line
      in byteStream.transform(utf8.decoder).transform(const LineSplitter())) {
    final String trimmed = line.trimRight();
    if (trimmed.isEmpty) {
      if (pending.isNotEmpty) {
        yield pending.toString().trimRight();
        pending.clear();
      }
      continue;
    }
    if (trimmed.startsWith(':')) continue;
    if (!trimmed.startsWith('data:')) continue;
    pending.writeln(trimmed.substring(5).trimLeft());
  }
  if (pending.isNotEmpty) yield pending.toString().trimRight();
}
