/// MCP 传输类型、server 配置与客户端异常。
library;

/// 传输类型。
enum McpTransportType { stdio, http, sse }

/// `initialize` 声明的能力集：本客户端关心的三项。
///
/// 只认这三项标准键：键存在且值非 `null` 即视为声明，缺失或未知一律
/// `false`——不认识的能力不能当成有。
class McpCapabilities {
  /// 直接构造；缺省全部为 `false`。
  const McpCapabilities({
    this.tools = false,
    this.resources = false,
    this.prompts = false,
  });

  /// 从 `initialize` 响应的 `capabilities` 对象解析。
  factory McpCapabilities.fromJson(Map<String, Object?> json) =>
      McpCapabilities(
        tools: json['tools'] != null,
        resources: json['resources'] != null,
        prompts: json['prompts'] != null,
      );

  /// 是否声明 `tools`（工具列表与调用）。
  final bool tools;

  /// 是否声明 `resources`（资源列表与读取）。
  final bool resources;

  /// 是否声明 `prompts`（提示词列表与取值）。
  final bool prompts;

  /// 三项能力都没声明。
  bool get none => !tools && !resources && !prompts;
}

/// 一台 MCP server 的连接配置。
///
/// 构造期即校验：名称非空；`stdio` 必须有 [command]，`http` / `sse` 必须有
/// [url]，不合规抛 [ArgumentError]——装配时就失败胜过连接时才失败。
///
/// [env] 与 [headers] 的值可以写 `${KEY}` 凭据占位符，由
/// `resolveCredentialPlaceholders` 在装配时解析。
class McpServerConfig {
  /// 构造并校验。
  McpServerConfig({
    required this.name,
    required this.type,
    this.command,
    this.args = const <String>[],
    this.env = const <String, String>{},
    this.url,
    this.headers = const <String, String>{},
  }) {
    _validate();
  }

  /// server 名：既做工具名前缀（`server__tool`），也做 [McpRegistry] 的键。
  final String name;

  /// 传输类型。
  final McpTransportType type;

  /// `stdio` 传输的可执行文件。
  final String? command;

  /// `stdio` 传输的命令行参数。
  final List<String> args;

  /// `stdio` 传输注入子进程的环境变量。
  final Map<String, String> env;

  /// `http` / `sse` 传输的端点地址。
  final String? url;

  /// `http` / `sse` 传输的附加请求头（如 `Authorization`）。
  final Map<String, String> headers;

  /// 复制并覆盖部分字段。
  ///
  /// 只能覆盖成非空值（沿用仓库里 `SessionEvent.copyWith` 的形状）；不能把
  /// [command] / [url] 改回 `null`。
  McpServerConfig copyWith({
    String? name,
    McpTransportType? type,
    String? command,
    List<String>? args,
    Map<String, String>? env,
    String? url,
    Map<String, String>? headers,
  }) =>
      McpServerConfig(
        name: name ?? this.name,
        type: type ?? this.type,
        command: command ?? this.command,
        args: args ?? this.args,
        env: env ?? this.env,
        url: url ?? this.url,
        headers: headers ?? this.headers,
      );

  void _validate() {
    if (name.isEmpty) {
      throw ArgumentError.value(name, 'name', 'MCP server 名不能为空');
    }
    _validateEndpoint();
  }

  void _validateEndpoint() {
    switch (type) {
      case McpTransportType.stdio:
        if (_blank(command)) {
          throw ArgumentError.value(
            command,
            'command',
            'stdio 传输需要 command',
          );
        }
      case McpTransportType.http:
      case McpTransportType.sse:
        if (_blank(url)) {
          throw ArgumentError.value(url, 'url', '$type 传输需要 url');
        }
    }
  }
}

/// MCP 客户端异常：稳定的机器可读码 + 人可读消息。
///
/// 常见 [code]：`timeout`、`disconnected`、`protocol-error`、
/// `malformed-result`、`too-many-pages`、`http-status`、`server-exited`。
class McpException implements Exception {
  /// 构造。
  const McpException(this.code, this.message);

  /// 错误码。
  final String code;

  /// 人可读说明。
  final String message;

  @override
  String toString() => 'McpException($code): $message';
}

bool _blank(String? value) => value == null || value.isEmpty;
