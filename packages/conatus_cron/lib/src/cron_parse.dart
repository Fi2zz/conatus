/// cron 表达式引擎：5 段字段解析、逐分钟匹配与下一个触发分钟搜索。
///
/// 字段支持 `*`、列表 `a,b`、范围 `a-b` 与步进 `*/n`、`a-b/n`、`a/n`（`a/n`
/// 按 Vixie cron 语义展开为 `a..max`）；周日 7 归一为 0；dom 与 dow 同时受限时
/// 任一匹配，否则两者都匹配。所有匹配都在本地时间进行。
library;

/// 5 段字段的取值范围：分、时、日、月、周（0 与 7 都表示周日）。
const List<({int min, int max})> kCronFieldRanges = <({int min, int max})>[
  (min: 0, max: 59),
  (min: 0, max: 23),
  (min: 1, max: 31),
  (min: 1, max: 12),
  (min: 0, max: 7),
];

/// [nextCronSlot] 的搜索上限：4 个闰年的毫秒数。
const int kCronSearchLimitMs = 4 * 366 * 24 * 60 * 60000;

/// 单个字段片段的形状：`*`、数字、范围与步进的组合。
final RegExp _fieldPartPattern = RegExp(r'^(\*|\d+)(?:-(\d+))?(?:\/(\d+))?$');

/// 解析后的 cron 表达式：5 个允许值集合 + dom/dow 是否裸星。
class CronExpression {
  /// 构造一个解析结果。
  CronExpression({
    required this.minute,
    required this.hour,
    required this.dom,
    required this.month,
    required this.dow,
    required this.domStar,
    required this.dowStar,
  });

  /// 允许的分钟集合。
  final Set<int> minute;

  /// 允许的小时集合。
  final Set<int> hour;

  /// 允许的日集合。
  final Set<int> dom;

  /// 允许的月集合。
  final Set<int> month;

  /// 允许的星期集合（0 表示周日）。
  final Set<int> dow;

  /// dom 字段是否为裸 `*`（标准 cron 语义用）。
  final bool domStar;

  /// dow 字段是否为裸 `*`（标准 cron 语义用）。
  final bool dowStar;
}

/// 一个字段片段展开后的上下界与步进。
class _FieldSlice {
  const _FieldSlice({required this.lo, required this.hi, required this.step});

  final int lo;
  final int hi;
  final int step;
}

/// 解析一个 cron 字段为允许值集合；任一片段非法返回 null。
Set<int>? parseCronField(String field, int min, int max) {
  final Set<int> values = <int>{};
  for (final String part in field.split(',')) {
    final _FieldSlice? slice = _parseFieldPart(part, min, max);
    if (slice == null) return null;
    for (int value = slice.lo; value <= slice.hi; value += slice.step) {
      values.add(value);
    }
  }
  return values.isNotEmpty ? values : null;
}

_FieldSlice? _parseFieldPart(String part, int min, int max) {
  final RegExpMatch? match = _fieldPartPattern.firstMatch(part);
  if (match == null) return null;
  final int step = match[3] == null ? 1 : int.parse(match[3]!);
  if (step < 1) return null;
  final _FieldSlice? bounds = _sliceBounds(match, min, max);
  if (bounds == null) return null;
  return _FieldSlice(lo: bounds.lo, hi: bounds.hi, step: step);
}

_FieldSlice? _sliceBounds(RegExpMatch match, int min, int max) {
  final String? base = match[1];
  final String? range = match[2];
  final String? stride = match[3];
  if (base == '*') return _FieldSlice(lo: min, hi: max, step: 1);
  final int lo = int.parse(base!);
  if (range != null) return _boundedSlice(lo, int.parse(range), min, max);
  if (stride != null) return _boundedSlice(lo, max, min, max);
  return _boundedSlice(lo, lo, min, max);
}

_FieldSlice? _boundedSlice(int lo, int hi, int min, int max) {
  final bool outOfRange = lo < min || hi > max || lo > hi;
  if (outOfRange) return null;
  return _FieldSlice(lo: lo, hi: hi, step: 1);
}

/// 解析标准 5 段表达式（分 时 日 月 周）；字段数不符或任一字段非法返回 null。
CronExpression? parseCronExpression(String expression) {
  final List<String> fields = expression.trim().split(RegExp(r'\s+'));
  if (fields.length != 5) return null;
  final List<Set<int>> parsed = <Set<int>>[];
  for (int i = 0; i < 5; i++) {
    final Set<int>? values = parseCronField(
        fields[i], kCronFieldRanges[i].min, kCronFieldRanges[i].max);
    if (values == null) return null;
    parsed.add(values);
  }
  if (parsed[4].remove(7)) parsed[4].add(0);
  return CronExpression(
    minute: parsed[0],
    hour: parsed[1],
    dom: parsed[2],
    month: parsed[3],
    dow: parsed[4],
    domStar: fields[2] == '*',
    dowStar: fields[4] == '*',
  );
}

/// 表达式是否匹配某个本地时间（分钟级精度由调用方保证）。
bool cronMatches(CronExpression cron, DateTime date) {
  if (!_timeMatches(cron, date)) return false;
  final bool domMatch = cron.dom.contains(date.day);
  final bool dowMatch = cron.dow.contains(date.weekday % 7);
  if (cron.domStar || cron.dowStar) return domMatch && dowMatch;
  return domMatch || dowMatch;
}

bool _timeMatches(CronExpression cron, DateTime date) {
  final bool hourMinute =
      cron.minute.contains(date.minute) && cron.hour.contains(date.hour);
  return hourMinute && cron.month.contains(date.month);
}

/// [after] 之后第一个匹配的本地分钟（严格大于）；4 年内无匹配返回 null。
DateTime? nextCronSlot(CronExpression cron, DateTime after) {
  int candidate = (after.millisecondsSinceEpoch ~/ 60000) * 60000 + 60000;
  final int limit = candidate + kCronSearchLimitMs;
  while (candidate < limit) {
    final DateTime instant =
        DateTime.fromMillisecondsSinceEpoch(candidate, isUtc: true);
    if (cronMatches(cron, instant.toLocal())) return instant;
    candidate += 60000;
  }
  return null;
}
