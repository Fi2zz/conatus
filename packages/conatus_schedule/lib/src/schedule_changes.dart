/// 持久 `schedule/change` 事件的严格解码：拒绝未知版本、未知操作、额外字段、
/// 非法标识、非规范时刻与形状不符的 dispatch。
library;

import 'dart:convert';

import 'schedule_errors.dart';
import 'schedule_time.dart';
import 'schedule_types.dart';

/// 一条已解码的持久变更。
sealed class ScheduleChange {
  /// 构造一条变更。
  const ScheduleChange();
}

/// 创建一条提醒记录。
class ScheduleCreateChange extends ScheduleChange {
  /// 构造一条创建变更。
  const ScheduleCreateChange(this.record);

  /// 新建的持久记录。
  final ScheduleRecord record;
}

/// 删除一条活动提醒。
class ScheduleDeleteChange extends ScheduleChange {
  /// 构造一条删除变更。
  const ScheduleDeleteChange(this.id);

  /// 目标标识。
  final String id;
}

/// 把一条提醒写入派发历史；固定间隔记录额外携带决策时点。
class ScheduleDispatchChange extends ScheduleChange {
  /// 构造一条派发变更。
  const ScheduleDispatchChange({required this.id, this.acceptedAt});

  /// 目标标识。
  final String id;

  /// 固定间隔决策的墙钟时点；一次性派发必须为 `null`。
  final DateTime? acceptedAt;
}

/// 解码一条持久变更；任何形状或取值违规都抛 [ScheduleLogException]。
ScheduleChange decodeScheduleChange(Object? value) {
  if (value is! Map<Object?, Object?>) {
    throw const ScheduleLogException(
        'schedule/change payload must be an object');
  }
  if (value['version'] != kScheduleChangeVersion) {
    throw const ScheduleLogException('schedule/change version must be 1');
  }
  switch (value['operation']) {
    case 'create':
      _requireExactKeys(
        value,
        const <String>['version', 'operation', 'schedule'],
        'schedule create must contain exactly version, operation, and schedule',
      );
      return ScheduleCreateChange(decodeScheduleRecord(value['schedule']));
    case 'delete':
      _requireExactKeys(
        value,
        const <String>['version', 'operation', 'id'],
        'schedule delete must contain exactly version, operation, and id',
      );
      return ScheduleDeleteChange(decodeScheduleId(value['id']));
    case 'dispatch':
      if (_exactKeys(value, const <String>['version', 'operation', 'id'])) {
        return ScheduleDispatchChange(id: decodeScheduleId(value['id']));
      }
      if (_exactKeys(
          value, const <String>['version', 'operation', 'id', 'acceptedAt'])) {
        return ScheduleDispatchChange(
          id: decodeScheduleId(value['id']),
          acceptedAt: decodeInstant(value['acceptedAt']),
        );
      }
      throw const ScheduleLogException(
          'schedule dispatch must contain id and optional acceptedAt only');
    default:
      throw const ScheduleLogException(
          'schedule/change operation must be create, delete, or dispatch');
  }
}

/// 解码一条持久记录；键集合必须与该种类完全一致。
ScheduleRecord decodeScheduleRecord(Object? value) {
  if (value is! Map<Object?, Object?>) {
    throw const ScheduleLogException('schedule record must be an object');
  }
  switch (value['kind']) {
    case 'after':
      return _decodeAfter(value);
    case 'at':
      return _decodeAt(value);
    case 'every':
      return _decodeEvery(value);
    default:
      throw const ScheduleLogException(
          'v1 schedule kind must be "after", "at", or "every"');
  }
}

/// 解码一个会话内标识：非空字符串且不带首尾空白。
String decodeScheduleId(Object? value) {
  if (value is! String || value.isEmpty || value.trim() != value) {
    throw const ScheduleLogException(
        'schedule id must be a non-empty string without surrounding whitespace');
  }
  return value;
}

ScheduleRecord _decodeAfter(Map<Object?, Object?> value) {
  _requireExactKeys(
    value,
    const <String>['id', 'kind', 'prompt', 'afterSeconds', 'scheduledAt'],
    'after schedule must contain exactly id, kind, prompt, afterSeconds, and scheduledAt',
  );
  final String prompt = _decodePrompt(value['prompt'], 'after');
  final Object? afterSeconds = value['afterSeconds'];
  if (afterSeconds is! int || !safePositiveSeconds(afterSeconds)) {
    throw const ScheduleLogException(
        'afterSeconds must be a positive safe integer');
  }
  return ScheduleRecord(
    id: decodeScheduleId(value['id']),
    kind: ScheduleKind.after,
    prompt: prompt,
    afterSeconds: afterSeconds,
    scheduledAt: decodeInstant(value['scheduledAt']),
  );
}

ScheduleRecord _decodeAt(Map<Object?, Object?> value) {
  _requireExactKeys(
    value,
    const <String>['id', 'kind', 'prompt', 'scheduledAt'],
    'at schedule must contain exactly id, kind, prompt, and scheduledAt',
  );
  return ScheduleRecord(
    id: decodeScheduleId(value['id']),
    kind: ScheduleKind.at,
    prompt: _decodePrompt(value['prompt'], 'at'),
    scheduledAt: decodeInstant(value['scheduledAt']),
  );
}

ScheduleRecord _decodeEvery(Map<Object?, Object?> value) {
  _requireExactKeys(
    value,
    const <String>['id', 'kind', 'prompt', 'everySeconds', 'scheduledAt'],
    'every schedule must contain exactly id, kind, prompt, everySeconds, and scheduledAt',
  );
  final String prompt = _decodePrompt(value['prompt'], 'every');
  final Object? everySeconds = value['everySeconds'];
  if (everySeconds is! int ||
      everySeconds < kMinEveryIntervalSeconds ||
      everySeconds > kMaxSafeInteger ~/ 1000) {
    throw const ScheduleLogException(
        'everySeconds must be a safe integer of at least $kMinEveryIntervalSeconds');
  }
  return ScheduleRecord(
    id: decodeScheduleId(value['id']),
    kind: ScheduleKind.every,
    prompt: prompt,
    everySeconds: everySeconds,
    scheduledAt: decodeInstant(value['scheduledAt']),
  );
}

String _decodePrompt(Object? value, String kind) {
  if (value is! String || value.isEmpty || value.trim() != value) {
    throw ScheduleLogException(
        '$kind prompt must be non-empty and already trimmed');
  }
  return value;
}

void _requireExactKeys(
  Map<Object?, Object?> value,
  List<String> expected,
  String message,
) {
  if (!_exactKeys(value, expected)) throw ScheduleLogException(message);
}

bool _exactKeys(Map<Object?, Object?> value, List<String> expected) {
  if (value.length != expected.length) return false;
  for (final String key in expected) {
    if (!value.containsKey(key)) return false;
  }
  return true;
}

/// 把标识渲染成可读的诊断片段（与源协议的引号形式一致）。
String quoteScheduleId(String id) => jsonEncode(id);
