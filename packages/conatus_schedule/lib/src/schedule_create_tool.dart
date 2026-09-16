/// `schedule_create`：在当前会话里创建一条提醒。
///
/// 选择器三选一，形状类错误在读取或决策之前返回，通过后才进入持久化检查点。
library;

import 'package:conatus_foundation/conatus_foundation.dart';

import 'schedule.dart';
import 'schedule_errors.dart';
import 'schedule_time.dart';
import 'schedule_tool_results.dart';
import 'schedule_types.dart';

/// 创建参数里允许出现的键。
const Set<String> kScheduleCreateKeys = <String>{
  'prompt',
  'after_seconds',
  'at',
  'every_seconds',
};

/// 在会话里创建一条提醒。
class ScheduleCreateTool extends Tool {
  /// 构造工具。
  const ScheduleCreateTool({required SessionSchedule schedule})
      : _schedule = schedule;

  final SessionSchedule _schedule;

  @override
  String get name => 'schedule_create';

  @override
  String get description =>
      'Create one reminder in the current session. Supply a non-empty prompt '
      'and exactly one selector: a positive safe-integer after_seconds delay, '
      'at as a strict offset date-time or local date/time object, or '
      'safe-integer every_seconds of at least $kMinEveryIntervalSeconds. '
      'A relative delay is measured from creation time; resolve relative '
      'dates against the current date given in the system prompt. When the '
      'request is vague (such as "later" or "in a while"), do not invent a '
      'delay: ask the user to pin down the timing first, or state the delay '
      'you chose in the reply so it can be corrected. '
      'Fixed-rate reminders stay creation-aligned, skip missed occurrences, and '
      'batch one latest occurrence per overdue rule. Delivery is session-local: '
      'the reminder runs on time only while this session is live and otherwise '
      'becomes overdue until the session is resumed.';

  @override
  ToolRisk get riskLevel => ToolRisk.medium;

  @override
  String? get group => 'schedule';

  @override
  List<ParamSpec> get params => <ParamSpec>[
        ParamSpec.string('prompt',
            required: true,
            description:
                'Reminder content to present when the target becomes due.'),
        ParamSpec.number('after_seconds',
            description:
                'Positive safe-integer delay in seconds, measured from '
                'creation time.'),
        ParamSpec.number('every_seconds',
            description: 'Fixed-rate safe-integer interval in seconds, at '
                'least $kMinEveryIntervalSeconds.'),
      ];

  /// 补齐 `at`：它是「字符串或对象」的联合，参数模型只表达单一类型。
  @override
  Map<String, Object?> toSchema() {
    final Map<String, Object?> schema = super.toSchema();
    final Object? parameters = schema['parameters'];
    if (parameters is Map<String, Object?>) {
      final Object? properties = parameters['properties'];
      if (properties is Map<String, Object?>) properties['at'] = _atSchema();
    }
    return schema;
  }

  @override
  Future<ToolResult> call(ToolContext context) async {
    final Map<String, Object?> args = context.arguments;
    final ({String code, String message})? invalid = validateCreateArgs(args);
    if (invalid != null) {
      return scheduleErrorResult(invalid.code, invalid.message);
    }
    return _create(args);
  }

  Future<ToolResult> _create(Map<String, Object?> args) async {
    try {
      final ScheduleView view = await _schedule.create(
        prompt: args['prompt']! as String,
        afterSeconds: asSafeInteger(args['after_seconds']),
        at: args['at'],
        everySeconds: asSafeInteger(args['every_seconds']),
      );
      return scheduleSuccessResult(view.toJson());
    } on ScheduleInputException catch (error) {
      return scheduleErrorResult(error.code, error.message);
    } on SchedulePersistenceException catch (error) {
      return schedulePersistenceResult(error);
    } on ScheduleLogException {
      return scheduleCorruptResult();
    } on Object {
      return scheduleInternalResult();
    }
  }

  // REASON: `at` 是字符串或本地对象的二选一联合，ParamSpec 表达不了联合类型；
  // 这里按协议补齐 oneOf，参数模型本身保持单类型不变。
  Map<String, Object?> _atSchema() => <String, Object?>{
        'description': 'Absolute target as strict offset RFC 3339 or local '
            'date/time with an explicit IANA zone.',
        'oneOf': <Object?>[
          <String, Object?>{'type': 'string'},
          <String, Object?>{
            'type': 'object',
            'properties': <String, Object?>{
              'date': <String, Object?>{'type': 'string'},
              'time': <String, Object?>{'type': 'string'},
              'time_zone': <String, Object?>{'type': 'string'},
            },
            'required': <String>['date', 'time', 'time_zone'],
          },
        ],
      };
}

/// 校验创建参数；返回 `null` 表示可以进入服务层。
({String code, String message})? validateCreateArgs(Map<String, Object?> args) {
  final ({String code, String message})? selector = _validateSelector(args);
  if (selector != null) return selector;
  return _validateRule(args);
}

({String code, String message})? _validateSelector(Map<String, Object?> args) {
  final bool unknown =
      args.keys.any((String key) => !kScheduleCreateKeys.contains(key));
  final int selectors = <Object?>[
    args['after_seconds'],
    args['at'],
    args['every_seconds'],
  ].where((Object? value) => value != null).length;
  if (unknown || selectors != 1) {
    return (
      code: ScheduleErrorCode.invalidSelector,
      message:
          'schedule_create accepts exactly one of after_seconds, at, or every_seconds.',
    );
  }
  final Object? prompt = args['prompt'];
  if (prompt is! String || prompt.trim().isEmpty) {
    return (
      code: ScheduleErrorCode.invalidPrompt,
      message: 'prompt must be non-empty after trimming.',
    );
  }
  return null;
}

({String code, String message})? _validateRule(Map<String, Object?> args) {
  final Object? after = args['after_seconds'];
  if (after != null) {
    final int? seconds = asSafeInteger(after);
    if (seconds == null || seconds <= 0) {
      return (
        code: ScheduleErrorCode.invalidRule,
        message: 'after_seconds must be a positive safe integer.',
      );
    }
  }
  final Object? every = args['every_seconds'];
  if (every != null) return _validateEvery(every);
  return null;
}

({String code, String message})? _validateEvery(Object raw) {
  final int? seconds = asSafeInteger(raw);
  if (seconds == null) {
    return (
      code: ScheduleErrorCode.invalidRule,
      message: 'every_seconds must be a safe integer.',
    );
  }
  if (seconds < kMinEveryIntervalSeconds) {
    return (
      code: ScheduleErrorCode.frequencyTooHigh,
      message: 'every_seconds must be at least $kMinEveryIntervalSeconds.',
    );
  }
  return null;
}

/// 把 JSON 数值收窄为安全整数；不是整数值或超出安全范围时返回 `null`。
int? asSafeInteger(Object? value) {
  if (value is int) {
    return value.abs() <= kMaxSafeInteger ? value : null;
  }
  if (value is double && value.isFinite && value == value.roundToDouble()) {
    return value.abs() <= kMaxSafeInteger ? value.toInt() : null;
  }
  return null;
}
