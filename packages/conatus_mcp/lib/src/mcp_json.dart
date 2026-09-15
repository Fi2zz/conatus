/// MCP 解析用的 JSON 取值助手（内部实现，不对外导出）。
///
/// 线协议字段是宽松的，服务端形态各异，因此解析一律「收窄失败即退回缺省」，
/// 不抛错、不中断整条消息。
library;

import 'dart:convert';

/// 解析一段 JSON；格式不合法返回 `null` 而不抛错。
Object? mcpDecode(String text) {
  try {
    return jsonDecode(text);
  } on FormatException {
    return null;
  }
}

/// 把 [value] 收窄为字符串映射。
///
/// `jsonDecode` 产出的是 `Map<String, dynamic>`，它是 `Map<String, Object?>`
/// 的子类型，因此可直接命中；非映射返回 `null`。
Map<String, Object?>? mcpMap(Object? value) =>
    value is Map<String, Object?> ? value : null;

/// 把 [value] 收窄为字符串；非字符串返回 `null`。
String? mcpString(Object? value) => value is String ? value : null;

/// 把 [value] 收窄为整数；非整数（如 `1.0`、`"1"`）返回 `null`。
int? mcpInt(Object? value) => value is int ? value : null;

/// 把 [value] 收窄为列表；非列表返回空列表。
List<Object?> mcpList(Object? value) =>
    value is List ? value : const <Object?>[];
