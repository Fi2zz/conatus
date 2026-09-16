/// time-context 插件：把「今天」作为日粒度锚点注入 system prompt。
///
/// 模型没有时钟，相对日期（"明天""下周三"）与带本地语义的时刻（"明早九点"）都
/// 需要一个外部锚点才能换算成绝对时间。这里注册一份 [PromptContext]，每轮装配
/// 重新求值，因此跨天自动更新；精确到秒的场景仍交给时间工具。
///
/// ```dart
/// provideSystemPrompt(app);
/// provideTimePrompt(app);
/// ```
library;

import 'package:conatus_core/conatus_core.dart';

import 'prompt_types.dart';
import 'system_prompt.dart';

/// 时间锚点在 system prompt 里的名字。
const String kTimeContextName = 'time';

/// 时间锚点在上下文之间的排序权重（靠前）。
const int kTimeContextOrder = -10;

/// 把日粒度的当前日期注册为一份动态上下文（日期 + 星期 + 时区）。
///
/// [prompt] 缺省取当前上下文提供的 `'systemPrompt'` 服务；[clock] 缺省用
/// [DateTime.now]；[zoneName] 给出时按它展示时区（如 IANA 名），否则用本地时区名。
/// 返回撤销函数（幂等）。
///
/// 锚点只精确到日：system 是可缓存前缀，秒级变化会让缓存每轮失效。
Disposer provideTimePrompt(
  Context ctx, {
  SystemPrompt? prompt,
  DateTime Function()? clock,
  String? zoneName,
}) {
  final SystemPrompt target =
      prompt ?? ctx.require<SystemPrompt>('systemPrompt');
  final DateTime Function() source = clock ?? DateTime.now;
  return target.context(PromptContext(
    name: kTimeContextName,
    order: kTimeContextOrder,
    text: () => _renderAnchor(source(), zoneName: zoneName),
  ));
}

/// 把时区偏移格式化为 `±HH:MM`（例如 `+08:00`、`-05:30`）。
String formatClockOffset(Duration offset) {
  final String sign = offset.isNegative ? '-' : '+';
  final int minutes = offset.inMinutes.abs();
  return '$sign${_pad(minutes ~/ 60)}:${_pad(minutes % 60)}';
}

String _renderAnchor(DateTime now, {String? zoneName}) {
  final String zone = zoneName ?? now.timeZoneName;
  final String weekday = _weekdayNames[now.weekday - 1];
  return '[当前时间]\n${_formatDate(now)} 周$weekday · '
      '$zone (UTC${formatClockOffset(now.timeZoneOffset)})';
}

String _formatDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${_pad(value.month)}-'
    '${_pad(value.day)}';

String _pad(int value) => value.toString().padLeft(2, '0');

const List<String> _weekdayNames = <String>['一', '二', '三', '四', '五', '六', '日'];
