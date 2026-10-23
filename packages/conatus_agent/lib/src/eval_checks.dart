/// 评估断言：对一次实测结果做确定性判断。
///
/// 断言是纯数据、可 JSON 往返，便于把一套测试冻结下来供多个候选共用。
library;

import 'eval_types.dart';

/// 一条评估断言的基类。
sealed class EvalCheck {
  const EvalCheck();

  /// 从 JSON 还原；未知类型抛 [FormatException]。
  factory EvalCheck.fromJson(Map<String, Object?> json) {
    final String type = '${json['type'] ?? ''}';
    return switch (type) {
      'output_contains' => OutputContains(
          '${json['text'] ?? ''}',
          absent: json['absent'] == true,
        ),
      'output_matches' => OutputMatches(
          '${json['pattern'] ?? ''}',
          absent: json['absent'] == true,
        ),
      'tool_use' => ToolUse(
          '${json['tool'] ?? ''}',
          required: json['required'] != false,
        ),
      'rounds_within' => RoundsWithin((json['max'] as num?)?.toInt() ?? 0),
      _ => throw FormatException('未知断言类型：$type'),
    };
  }

  /// 对 [result] 求值。
  bool evaluate(EvalResult result);

  /// 序列化。
  Map<String, Object?> toJson();
}

/// 输出包含（或不得包含）指定文本。
final class OutputContains extends EvalCheck {
  const OutputContains(this.text, {this.absent = false});

  /// 目标文本。
  final String text;

  /// true 表示断言「不得包含」。
  final bool absent;

  @override
  bool evaluate(EvalResult result) =>
      result.actualOutput.contains(text) != absent;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'type': 'output_contains',
        'text': text,
        'absent': absent,
      };
}

/// 输出匹配（或不匹配）正则。
final class OutputMatches extends EvalCheck {
  OutputMatches(this.pattern, {this.absent = false}) {
    RegExp(pattern); // 构造时校验，非法正则立即抛 FormatException
  }

  /// 正则源码。
  final String pattern;

  /// true 表示断言「不匹配」。
  final bool absent;

  @override
  bool evaluate(EvalResult result) =>
      RegExp(pattern).hasMatch(result.actualOutput) != absent;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'type': 'output_matches',
        'pattern': pattern,
        'absent': absent,
      };
}

/// 工具调用断言：必须调用 / 不得调用。
final class ToolUse extends EvalCheck {
  const ToolUse(this.tool, {this.required = true});

  /// 工具名。
  final String tool;

  /// true 表示必须出现；false 表示不得出现。
  final bool required;

  @override
  bool evaluate(EvalResult result) =>
      result.actualTools.contains(tool) == required;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'type': 'tool_use',
        'tool': tool,
        'required': required,
      };
}

/// 步数上限。
final class RoundsWithin extends EvalCheck {
  const RoundsWithin(this.max);

  /// 允许的最大工具步数。
  final int max;

  @override
  bool evaluate(EvalResult result) => result.rounds <= max;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'type': 'rounds_within',
        'max': max,
      };
}
