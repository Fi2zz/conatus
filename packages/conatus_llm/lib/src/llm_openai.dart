/// OpenAI 兼容 provider：Chat Completions / Responses 双形态的 wire 层。
///
/// 请求按 [LlmApiStyle] 选择端点与载荷：
///
/// * chat — `messages: [{role, content}]`；
/// * responses — `input: [{type: 'message', role, content: [...]}]`，并显式
///   `store: false`（与引擎侧一致，避免敏感原文留存服务端）。
///
/// 响应侧：非流式解析 `choices[].message.content` 或 `output[].content[]
/// .output_text`；流式解析 SSE `data:` 帧，Chat 取 `choices[].delta`，
/// Responses 按事件 `type` 取 `response.output_text.delta` 等增量。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:conatus_credentials/conatus_credentials.dart';
import 'package:http/http.dart' as http;
import 'llm.dart';

/// LLM 请求的默认 User-Agent。
const String kDefaultLlmUserAgent = 'ConatusCode/0.16';

/// 处理 OpenAI 兼容端点的公共逻辑。
abstract class _OpenAiCompatibleProvider implements LlmProvider {
  _OpenAiCompatibleProvider({
    required String? apiKey,
    required this.baseUrl,
    required this.model,
    required this.credentialKey,
    this.apiStyle = LlmApiStyle.chat,
    this.userAgent = kDefaultLlmUserAgent,
    http.Client? client,
    Credentials? credentials,
    this.timeout = const Duration(seconds: 60),
  })  : apiKey = _resolveApiKey(apiKey, credentials, credentialKey),
        _client = client ?? http.Client() {
    _watchCredentials(credentials);
  }

  /// 当前 API Key。构造期按 `apiKey` → 凭据服务 → 环境变量解析；
  /// 之后由凭据服务的变更流就地轮换，故不是 `final`。
  String apiKey;

  /// 凭据服务里对应的键名（如 `ARK_API_KEY`）。
  final String credentialKey;
  final String baseUrl;
  final String model;
  final LlmApiStyle apiStyle;

  /// 请求携带的 User-Agent（可伪装成其他 harness 客户端）。
  final String userAgent;
  final Duration timeout;

  /// HTTP client。Key 轮换只改 [apiKey]，而 `_headers` 每次请求重算，因此
  /// **不**因轮换重建 client——重建反而会在 [close] 后留下悬挂实例。
  final http.Client _client;
  StreamSubscription<Credential>? _credentialsSubscription;

  /// 构造期解析顺序：显式 `apiKey` → 凭据服务（缺省 `EnvCredentials` 由调用方
  /// 经 `provideCredentials` 注入）。**不直接读环境变量**——需要环境变量时用
  /// `EnvCredentials` 作为凭据来源。
  static String _resolveApiKey(
    String? apiKey,
    Credentials? credentials,
    String credentialKey,
  ) =>
      apiKey ?? credentials?.get(credentialKey)?.value ?? '';

  void _watchCredentials(Credentials? credentials) {
    if (credentials == null || credentialKey.isEmpty) return;
    _credentialsSubscription = credentials.changes.listen(_applyCredential);
  }

  void _applyCredential(Credential credential) {
    if (credential.key != credentialKey) return;
    if (credential.expired) return;
    apiKey = credential.value;
  }

  bool get _responses => apiStyle == LlmApiStyle.responses;

  Uri get _endpoint =>
      Uri.parse('$baseUrl/${_responses ? 'responses' : 'chat/completions'}');

  Map<String, String> get _headers => <String, String>{
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
        'User-Agent': userAgent,
      };

  // ═══════════════════════════════════════════════════════════════
  // 请求体
  // ═══════════════════════════════════════════════════════════════

  Map<String, dynamic> _body(
    List<LlmMessage> messages, {
    required bool stream,
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) {
    final Map<String, dynamic> body = <String, dynamic>{
      'model': model,
      if (_responses) ...<String, dynamic>{
        'input': _responsesInput(messages),
        'store': false,
      } else
        'messages': <Map<String, dynamic>>[
          for (final LlmMessage message in messages) message.toJson(),
        ],
      if (stream) 'stream': true,
      if (stream && !_responses)
        'stream_options': <String, bool>{'include_usage': true},
      if (tools != null && tools.isNotEmpty)
        'tools': _responses ? _responsesTools(tools) : _chatTools(tools),
    };
    if (options != null) body.addAll(options);
    return body;
  }

  List<Map<String, dynamic>> _chatTools(List<Map<String, dynamic>> tools) =>
      <Map<String, dynamic>>[
        for (final Map<String, dynamic> tool in tools)
          <String, dynamic>{
            'type': 'function',
            'function': <String, dynamic>{
              'name': tool['name'],
              'description': tool['description'],
              'parameters': tool['parameters'],
            },
          },
      ];

  List<Map<String, dynamic>> _responsesTools(
          List<Map<String, dynamic>> tools) =>
      <Map<String, dynamic>>[
        for (final Map<String, dynamic> tool in tools)
          <String, dynamic>{
            'type': 'function',
            'name': tool['name'],
            'description': tool['description'],
            'parameters': tool['parameters'],
          },
      ];

  /// Responses input 项：普通消息、助手工具调用、工具结果各自映射。
  List<Map<String, dynamic>> _responsesInput(List<LlmMessage> messages) {
    final List<Map<String, dynamic>> items = <Map<String, dynamic>>[];
    for (final LlmMessage message in messages) {
      if (message.role == 'tool') {
        items.add(<String, dynamic>{
          'type': 'function_call_output',
          'call_id': message.toolCallId ?? '',
          'output': message.content,
        });
        continue;
      }
      if (message.toolCalls.isNotEmpty) {
        if (message.content.isNotEmpty) items.add(_responsesItem(message));
        for (final LlmToolCall call in message.toolCalls) {
          items.add(<String, dynamic>{
            'type': 'function_call',
            'call_id': call.id,
            'name': call.name,
            'arguments': call.arguments,
          });
        }
        continue;
      }
      items.add(_responsesItem(message));
    }
    return items;
  }

  /// Responses input 项。Ark /responses 强校验：message 项须带 type=message，
  /// assistant 历史项另须 status=completed。
  Map<String, dynamic> _responsesItem(LlmMessage message) {
    final bool assistant = message.role == 'assistant';
    return <String, dynamic>{
      'type': 'message',
      'role': message.role,
      if (assistant) 'status': 'completed',
      'content': <Map<String, String>>[
        <String, String>{
          'type': assistant ? 'output_text' : 'input_text',
          'text': message.content,
        },
        for (final LlmImage image in message.images)
          <String, String>{
            'type': 'input_image',
            'image_url': image.dataUrl,
          },
      ],
    };
  }

  // ═══════════════════════════════════════════════════════════════
  // 非流式
  // ═══════════════════════════════════════════════════════════════

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async {
    _requireKey();
    final http.Response response;
    try {
      response = await _client
          .post(
            _endpoint,
            headers: _headers,
            body: jsonEncode(
              _body(messages, stream: false, options: options, tools: tools),
            ),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw LlmException(name, '请求超时（${timeout.inSeconds}s）');
    } on SocketException catch (e) {
      throw LlmException(name, '网络错误：${e.message}');
    }

    if (response.statusCode != 200) {
      throw LlmException(name, response.body, response.statusCode);
    }

    final Map<String, dynamic> json =
        jsonDecode(response.body) as Map<String, dynamic>;
    return LlmResult(
      content: _responses ? _responsesText(json) : _chatText(json),
      provider: name,
      model: (json['model'] as String?) ?? model,
      usage: (json['usage'] as Map<String, dynamic>?) ?? <String, dynamic>{},
      toolCalls: _responses ? _responsesToolCalls(json) : _chatToolCalls(json),
    );
  }

  String _chatText(Map<String, dynamic> json) {
    final Map<String, dynamic>? message = _chatMessage(json);
    return (message?['content'] as String?) ?? '';
  }

  Map<String, dynamic>? _chatMessage(Map<String, dynamic> json) {
    final List<dynamic>? choices = json['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) {
      throw LlmException(name, '响应中没有 choices 字段');
    }
    final Map<String, dynamic> first = choices.first as Map<String, dynamic>;
    return (first['message'] as Map<String, dynamic>?) ?? <String, dynamic>{};
  }

  List<LlmToolCall> _chatToolCalls(Map<String, dynamic> json) {
    final Object? raw = _chatMessage(json)?['tool_calls'];
    if (raw is! List) return const <LlmToolCall>[];
    final List<LlmToolCall> calls = <LlmToolCall>[];
    for (final Object? item in raw) {
      if (item is! Map) continue;
      final Object? function = item['function'];
      if (function is! Map) continue;
      final Object? toolName = function['name'];
      if (toolName is! String) continue;
      calls.add(LlmToolCall(
        id: '${item['id'] ?? ''}',
        name: toolName,
        arguments: _argumentsText(function['arguments']),
      ));
    }
    return calls;
  }

  List<LlmToolCall> _responsesToolCalls(Map<String, dynamic> json) {
    final List<LlmToolCall> calls = <LlmToolCall>[];
    for (final Object? item
        in json['output'] as List<dynamic>? ?? const <dynamic>[]) {
      if (item is! Map<String, dynamic> || item['type'] != 'function_call') {
        continue;
      }
      final Object? toolName = item['name'];
      if (toolName is! String) continue;
      calls.add(LlmToolCall(
        id: '${item['call_id'] ?? item['id'] ?? ''}',
        name: toolName,
        arguments: _argumentsText(item['arguments']),
      ));
    }
    return calls;
  }

  String _argumentsText(Object? arguments) {
    if (arguments == null) return '{}';
    if (arguments is String) return arguments.isEmpty ? '{}' : arguments;
    return jsonEncode(arguments);
  }

  String _responsesText(Map<String, dynamic> json) {
    final StringBuffer buffer = StringBuffer();
    for (final dynamic item
        in json['output'] as List<dynamic>? ?? const <dynamic>[]) {
      if (item is! Map<String, dynamic> || item['type'] != 'message') continue;
      for (final dynamic part
          in item['content'] as List<dynamic>? ?? const <dynamic>[]) {
        if (part is Map<String, dynamic> && part['type'] == 'output_text') {
          buffer.write(part['text'] as String? ?? '');
        }
      }
    }
    return buffer.toString();
  }

  // ═══════════════════════════════════════════════════════════════
  // 流式
  // ═══════════════════════════════════════════════════════════════

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
      throw LlmException(name, '请求超时（${timeout.inSeconds}s）');
    } on SocketException catch (e) {
      throw LlmException(name, '网络错误：${e.message}');
    }

    if (response.statusCode != 200) {
      final String body = await response.stream.bytesToString();
      throw LlmException(name, body, response.statusCode);
    }

    final _StreamState state = _StreamState();
    await for (final String data in _sseData(response.stream)) {
      final Map<String, dynamic>? json = _tryDecode(data);
      if (json == null) continue;
      for (final LlmStreamEvent event in _frameEvents(json, state)) {
        yield event;
      }
    }
    yield LlmStreamDone(
      usage: state.usage,
      finishReason: state.finishReason,
      toolCalls: state.buildToolCalls(),
    );
  }

  List<LlmStreamEvent> _frameEvents(
    Map<String, dynamic> json,
    _StreamState state,
  ) =>
      _responses ? _responsesFrame(json, state) : _chatFrame(json, state);

  List<LlmStreamEvent> _chatFrame(
    Map<String, dynamic> json,
    _StreamState state,
  ) {
    final Map<String, dynamic>? usage = json['usage'] as Map<String, dynamic>?;
    if (usage != null) state.usage = usage;

    final List<dynamic> choices =
        json['choices'] as List<dynamic>? ?? const <dynamic>[];
    if (choices.isEmpty) return const <LlmStreamEvent>[];

    final Map<String, dynamic> choice = choices.first as Map<String, dynamic>;
    final Map<String, dynamic> delta =
        (choice['delta'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    state.finishReason =
        (choice['finish_reason'] as String?) ?? state.finishReason;

    final List<LlmStreamEvent> events = <LlmStreamEvent>[];
    final String? reasoning = delta['reasoning_content'] as String?;
    if (reasoning != null && reasoning.isNotEmpty) {
      events.add(LlmReasoningDelta(reasoning));
    }
    final String? content = delta['content'] as String?;
    if (content != null && content.isNotEmpty) {
      events.add(LlmTextDelta(content));
    }
    _accumulateChatToolCalls(delta['tool_calls'], state);
    return events;
  }

  /// Chat Completions 的 `delta.tool_calls`：按 `index` 键累积 id / name /
  /// arguments 分片。首个分片通常带 `id` 与 `function.name`，后续只补 arguments。
  void _accumulateChatToolCalls(Object? rawCalls, _StreamState state) {
    if (rawCalls is! List) return;
    for (final Object? rawCall in rawCalls) {
      if (rawCall is! Map) continue;
      final int index =
          (rawCall['index'] as int?) ?? state.chatToolCalls.length;
      final _ToolCallBuilder builder = state.chatBuilder(index);
      final Object? id = rawCall['id'];
      if (id is String && id.isNotEmpty) builder.id = id;
      final Object? function = rawCall['function'];
      if (function is! Map) continue;
      final Object? name = function['name'];
      if (name is String && name.isNotEmpty) builder.name = name;
      builder.addArguments(function['arguments']);
    }
  }

  List<LlmStreamEvent> _responsesFrame(
    Map<String, dynamic> json,
    _StreamState state,
  ) {
    switch (json['type'] as String? ?? '') {
      case 'response.output_text.delta':
        final String delta = (json['delta'] as String?) ?? '';
        return delta.isEmpty
            ? const <LlmStreamEvent>[]
            : <LlmStreamEvent>[LlmTextDelta(delta)];
      case 'response.reasoning_summary_text.delta':
      case 'response.reasoning_text.delta':
        final String delta = (json['delta'] as String?) ?? '';
        return delta.isEmpty
            ? const <LlmStreamEvent>[]
            : <LlmStreamEvent>[LlmReasoningDelta(delta)];
      case 'response.output_item.added':
        _accumulateResponsesItem(json['item'], state);
        return const <LlmStreamEvent>[];
      case 'response.function_call_arguments.delta':
        _appendResponsesArguments(json, state);
        return const <LlmStreamEvent>[];
      case 'response.function_call_arguments.done':
        _setResponsesArguments(json, state);
        return const <LlmStreamEvent>[];
      case 'response.output_item.done':
        _accumulateResponsesItem(json['item'], state);
        return const <LlmStreamEvent>[];
      case 'response.completed':
      case 'response.incomplete':
        final Map<String, dynamic> data =
            (json['response'] as Map<String, dynamic>?) ?? <String, dynamic>{};
        final Map<String, dynamic>? usage =
            data['usage'] as Map<String, dynamic>?;
        if (usage != null) state.usage = usage;
        state.finishReason = json['type'] == 'response.incomplete'
            ? 'length'
            : ((data['status'] as String?) ?? 'completed');
        return const <LlmStreamEvent>[];
      case 'response.failed':
        final Map<String, dynamic> data =
            (json['response'] as Map<String, dynamic>?) ?? <String, dynamic>{};
        final Map<String, dynamic> error =
            (data['error'] as Map<String, dynamic>?) ?? <String, dynamic>{};
        throw LlmException(name, '流式响应失败：${error['message'] ?? 'unknown'}');
      default:
        return const <LlmStreamEvent>[];
    }
  }

  /// Responses 输出项：`function_call` 项携带 call_id / name / arguments。
  /// 首帧（`output_item.added`）与终帧（`output_item.done`）各调一次，
  /// 终帧的 arguments 为权威完整值。
  void _accumulateResponsesItem(Object? rawItem, _StreamState state) {
    if (rawItem is! Map<String, dynamic> ||
        rawItem['type'] != 'function_call') {
      return;
    }
    final _ToolCallBuilder builder =
        state.responsesBuilder('${rawItem['id'] ?? ''}');
    final Object? callId = rawItem['call_id'];
    if (callId is String && callId.isNotEmpty) builder.id = callId;
    final Object? name = rawItem['name'];
    if (name is String && name.isNotEmpty) builder.name = name;
    builder.setArguments(rawItem['arguments']);
  }

  /// `response.function_call_arguments.delta`：追加 arguments 分片。
  void _appendResponsesArguments(
    Map<String, dynamic> json,
    _StreamState state,
  ) =>
      state.responsesBuilder('${json['item_id'] ?? ''}').addArguments(
            json['delta'],
          );

  /// `response.function_call_arguments.done`：以完整 arguments 覆盖。
  void _setResponsesArguments(
    Map<String, dynamic> json,
    _StreamState state,
  ) =>
      state
          .responsesBuilder('${json['item_id'] ?? ''}')
          .setArguments(json['arguments']);

  void _requireKey() {
    if (apiKey.isEmpty) {
      throw LlmException(
        name,
        credentialKey.isEmpty
            ? '缺少 API Key'
            : '缺少 API Key（凭据键：$credentialKey 未配置）',
      );
    }
  }

  /// 释放：取消凭据变更订阅，并关闭 HTTP client。
  @override
  void close() {
    unawaited(_credentialsSubscription?.cancel());
    _credentialsSubscription = null;
    _client.close();
  }
}

/// 流式累积状态：用量、结束原因与工具调用分片可能晚于增量到达，收尾时统一产出。
class _StreamState {
  Map<String, dynamic> usage = const <String, dynamic>{};
  String? finishReason;

  /// Chat Completions：按 `tool_calls[].index` 累积。
  final List<_ToolCallBuilder> chatToolCalls = <_ToolCallBuilder>[];

  /// Responses：按输出项 `id` 累积。
  final Map<String, _ToolCallBuilder> responsesToolCalls =
      <String, _ToolCallBuilder>{};

  _ToolCallBuilder chatBuilder(int index) {
    while (chatToolCalls.length <= index) {
      chatToolCalls.add(_ToolCallBuilder());
    }
    return chatToolCalls[index];
  }

  _ToolCallBuilder responsesBuilder(String itemId) =>
      responsesToolCalls.putIfAbsent(itemId, _ToolCallBuilder.new);

  /// 汇总已完成的工具调用；丢弃只收到分片、始终无名的占位项。
  List<LlmToolCall> buildToolCalls() => <LlmToolCall>[
        for (final _ToolCallBuilder builder in chatToolCalls) builder.build(),
        for (final _ToolCallBuilder builder in responsesToolCalls.values)
          builder.build(),
      ].where((LlmToolCall call) => call.name.isNotEmpty).toList();
}

/// 流式工具调用分片累积器：id / name 一次性到达，arguments 为 JSON 分片。
class _ToolCallBuilder {
  String id = '';
  String name = '';
  final StringBuffer _arguments = StringBuffer();

  /// 追加 arguments 分片；非字符串（如已解析的 Map）按 JSON 编码。
  void addArguments(Object? chunk) {
    if (chunk is String) {
      if (chunk.isNotEmpty) _arguments.write(chunk);
    } else if (chunk != null) {
      _arguments.write(jsonEncode(chunk));
    }
  }

  /// 以完整 arguments 覆盖；空串忽略（终帧缺省时不抹掉已累积分片）。
  void setArguments(Object? complete) {
    if (complete is! String || complete.isEmpty) return;
    _arguments
      ..clear()
      ..write(complete);
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

/// 响应字节流 → SSE `data:` 载荷流（UTF-8、忽略注释、处理 [DONE]）。
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
    if (trimmed.startsWith(':')) continue; // SSE 注释行。
    if (!trimmed.startsWith('data:')) continue; // event:/id: 等字段不使用。
    final String payload = trimmed.substring(5).trimLeft();
    if (payload == '[DONE]') {
      if (pending.isNotEmpty) {
        yield pending.toString().trimRight();
        pending.clear();
      }
      return;
    }
    pending.writeln(payload);
  }
  if (pending.isNotEmpty) {
    yield pending.toString().trimRight();
  }
}

// ═══════════════════════════════════════════════════════════════
// 通用 OpenAI 兼容端点
// ═══════════════════════════════════════════════════════════════

/// 通用 OpenAI 兼容提供商：端点 / 模型 / 凭据键全部由调用方指定。
///
/// 用于自建网关、第三方聚合等任意 OpenAI 兼容服务；豆包与 DeepSeek 保留各自的
/// 专用子类（默认端点与凭据键不同）。
class OpenAiCompatibleProvider extends _OpenAiCompatibleProvider {
  OpenAiCompatibleProvider({
    required this.name,
    required super.baseUrl,
    required super.model,
    super.credentialKey = '',
    super.apiKey,
    super.apiStyle,
    super.userAgent,
    super.client,
    super.credentials,
    super.timeout,
  });

  /// 展示名（如 `'opencode-go'`）。
  @override
  final String name;
}
