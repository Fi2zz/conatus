/// 行分割工具：统一处理 CRLF，保留结尾换行语义。
library;

/// 按 `\n` 分割并去掉每行末尾的 `\r`。
List<String> splitTextLines(String input) => input
    .split('\n')
    .map((String line) =>
        line.endsWith('\r') ? line.substring(0, line.length - 1) : line)
    .toList();

/// 按原换行风格重新拼接。
String joinTextLines(List<String> lines, {required bool crlf}) =>
    lines.join(crlf ? '\r\n' : '\n');

/// 输入是否使用 CRLF。
bool usesCrlf(String input) => input.contains('\r\n');
