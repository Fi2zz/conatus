/// 成员活动：把「某个成员此刻在干什么」变成可流式消费的值对象。
///
/// 成员状态只有 idle / working / waiting 这几档，看不出它在干活还是在卡住。
/// 一次 `wait_agent` 可能是 5 秒也可能是 5 分钟，界面必须能实时显示它读了哪个
/// 文件、调了什么工具、已经说了什么——否则用户只能干等。
library;

/// 成员的一次活动。
sealed class TeammateActivity {
  const TeammateActivity();

  /// 活动类型名。
  String get kind;
}

/// 正文增量。
class TeammateText extends TeammateActivity {
  const TeammateText(this.text);

  /// 增量文本。
  final String text;

  @override
  String get kind => 'text';
}

/// 思考增量。
class TeammateReasoning extends TeammateActivity {
  const TeammateReasoning(this.text);

  /// 增量文本。
  final String text;

  @override
  String get kind => 'reasoning';
}

/// 要调一个工具。
class TeammateToolCall extends TeammateActivity {
  const TeammateToolCall(this.tool);

  /// 工具名。
  final String tool;

  @override
  String get kind => 'tool-call';
}

/// 工具返回了。
class TeammateToolResult extends TeammateActivity {
  const TeammateToolResult(this.tool, {this.failed = false, this.preview = ''});

  /// 工具名。
  final String tool;

  /// 是否失败。
  final bool failed;

  /// 结果摘要；换行由 [activityLine] 收成一行。
  final String preview;

  @override
  String get kind => 'tool-result';
}

/// 一轮开始。
class TeammateRoundStart extends TeammateActivity {
  const TeammateRoundStart(this.round);

  /// 第几轮（1 起）。
  final int round;

  @override
  String get kind => 'round-start';
}

/// 屏上一行回执；`indent` 为泳道缩进。
///
/// 活动是给**界面**看的，不是给模型看的——模型只需要成员最终的结论。
class TeammateActivityLine {
  const TeammateActivityLine(this.text, {this.failed = false});

  /// 屏上直接显示的一行。
  final String text;

  /// 是否失败（决定图标与颜色）。
  final bool failed;

  @override
  String toString() => text;
}

/// 活动 → 屏上一行。每一类都必须收成**单行**——泳道是定高的，多行会把整
/// 个视图撑开，其它成员被挤出视野。
TeammateActivityLine activityLine(TeammateActivity activity) =>
    switch (activity) {
      TeammateText(:final String text) => TeammateActivityLine(_clip(text, 120)),
      TeammateReasoning(:final String text) =>
        TeammateActivityLine('思考 ${_clip(text, 80)}'),
      TeammateToolCall(:final String tool) => TeammateActivityLine('→ $tool'),
      TeammateToolResult(:final String tool, :final bool failed,
          :final String preview) =>
        TeammateActivityLine(
          '${failed ? '✗' : '✓'} $tool${preview.isEmpty ? '' : ' · ${_clip(preview, 60)}'}',
          failed: failed,
        ),
      TeammateRoundStart(:final int round) =>
        TeammateActivityLine('· 第 $round 轮'),
    };

/// 截断到 [limit] 字符，并压掉换行（取首行）。
String _clip(String text, int limit) {
  final String flat = text.trim().split('\n').first.trim();
  return flat.length <= limit ? flat : '${flat.substring(0, limit)}…';
}
