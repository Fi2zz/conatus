/// MCP 线协议的 JSON-RPC 2.0 词汇：协议版本、错误对象与消息信封。
///
/// 本文件只做数据搬运，不依赖任何 conatus 类型，可单独用于协议调试。
library;

import 'mcp_json.dart';

/// 本客户端在 `initialize` 中声明的 MCP 协议版本。
///
/// 服务端可能回一个不同版本：客户端只记录不拒绝（见 [McpServerInfo]）。
const String kMcpProtocolVersion = '2025-06-18';

/// JSON-RPC 2.0 错误对象。
class McpError {
  /// 构造一个错误对象；[data] 是服务端自定义的附加信息。
  const McpError(this.code, this.message, {this.data});

  /// 从 JSON 解析；`code` / `message` 缺失时退回零值而非抛错。
  factory McpError.fromJson(Map<String, Object?> json) => McpError(
        mcpInt(json['code']) ?? 0,
        mcpString(json['message']) ?? '',
        data: json['data'],
      );

  /// 错误码：JSON-RPC 标准码或服务端自定义码。
  final int code;

  /// 人可读的错误说明。
  final String message;

  /// 附加数据；随服务端而定，可能为 `null`。
  final Object? data;

  /// 序列化为 JSON。
  Map<String, Object?> toJson() => <String, Object?>{
        'code': code,
        'message': message,
        if (data != null) 'data': data,
      };

  @override
  String toString() => 'McpError($code): $message';
}

/// 一条 JSON-RPC 消息：请求 / 通知 / 响应三态合一。
///
/// 三态由字段组合判定：`method` 与 `id` 俱全的是 [request]；只有 `method`
/// 的是 [notification]（单向，不期待回复）；没有 `method` 的是 [response]。
class McpMessage {
  /// 直接构造；一般用 [McpMessage.request] / [McpMessage.notification]。
  const McpMessage(
      {this.id, this.method, this.params, this.result, this.error});

  /// 构造请求。
  factory McpMessage.request({
    required Object id,
    required String method,
    Map<String, Object?>? params,
  }) =>
      McpMessage(id: id, method: method, params: params);

  /// 构造通知。
  factory McpMessage.notification({
    required String method,
    Map<String, Object?>? params,
  }) =>
      McpMessage(method: method, params: params);

  /// 从 JSON 解析；字段形态不合法时该字段为 `null`，不抛错。
  factory McpMessage.fromJson(Map<String, Object?> json) => McpMessage(
        id: json['id'],
        method: mcpString(json['method']),
        params: mcpMap(json['params']),
        result: json['result'],
        error: _errorOf(json['error']),
      );

  /// 消息 id；请求与响应有，通知没有。
  final Object? id;

  /// 方法名；响应没有。
  final String? method;

  /// 调用参数；无参时为 `null`。
  final Map<String, Object?>? params;

  /// 成功结果；非响应或失败时为 `null`。
  final Object? result;

  /// 失败信息；非失败响应时为 `null`。
  final McpError? error;

  /// 是否需要服务端回一条响应。
  bool get request => method != null && id != null;

  /// 是否是单向通知。
  bool get notification => method != null && id == null;

  /// 是否是响应。
  bool get response => method == null;

  /// 序列化为 JSON；`jsonrpc` 固定为 `2.0`。
  Map<String, Object?> toJson() => <String, Object?>{
        'jsonrpc': '2.0',
        if (method != null) 'method': method,
        if (params != null) 'params': params,
        if (id != null) 'id': id,
        if (error != null) 'error': error!.toJson(),
        if (response && error == null) 'result': result,
      };

  @override
  String toString() =>
      'McpMessage(${method ?? 'id=$id'}${error == null ? '' : ' $error'})';
}

/// `initialize` 的握手结果。
class McpServerInfo {
  /// 构造。
  const McpServerInfo({
    required this.protocolVersion,
    this.name,
    this.version,
    this.instructions,
    this.capabilities = const <String, Object?>{},
  });

  /// 从 `initialize` 响应的 `result` 解析。
  ///
  /// 标准的形态是 `{protocolVersion, capabilities, serverInfo: {name,
  /// version}}`；也接受把 `name` / `version` 直接放在顶层的宽容形态。
  /// 服务端返回的协议版本照收不误（只记录，不拒绝）。
  factory McpServerInfo.fromJson(Map<String, Object?> json) {
    final Map<String, Object?> info = mcpMap(json['serverInfo']) ?? json;
    return McpServerInfo(
      protocolVersion:
          mcpString(json['protocolVersion']) ?? kMcpProtocolVersion,
      name: mcpString(info['name']),
      version: mcpString(info['version']),
      instructions: mcpString(json['instructions']),
      capabilities: mcpMap(json['capabilities']) ?? const <String, Object?>{},
    );
  }

  /// 服务端声明的协议版本。
  final String protocolVersion;

  /// 服务端名（`serverInfo.name`）。
  final String? name;

  /// 服务端版本（`serverInfo.version`）。
  final String? version;

  /// 给模型的用法说明（可选）。
  final String? instructions;

  /// 能力声明（`tools` / `resources` / `prompts` ...）。
  final Map<String, Object?> capabilities;
}

McpError? _errorOf(Object? value) {
  final Map<String, Object?>? json = mcpMap(value);
  return json == null ? null : McpError.fromJson(json);
}
