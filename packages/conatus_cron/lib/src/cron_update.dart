/// 任务编辑规则：patch 合并、规则替换与运行戳重置。
///
/// 语义与 dsh-cron 的 updateDynamicTask 一致：patch 含任何规则键则整组规则
/// 替换（其余规则清空）并重置运行戳，使新规则立即生效；仅 prompt 则原地更新。
library;

import 'cron_errors.dart';
import 'cron_parse.dart';
import 'cron_rules.dart';
import 'cron_types.dart';

/// patch 是否触碰任何调度规则键。
bool patchTouchesSchedule(Map<String, Object?> patch) =>
    kCronRuleKeys.any((String key) => patch[key] != null);

/// 规范化 prompt：去首尾空白并拒绝空内容（update 路径；add 路径保留原文）。
String normalizeCronPrompt(Object? prompt) {
  final String normalized = prompt is String ? prompt.trim() : '';
  if (normalized.isEmpty) {
    throw const CronException(
        CronErrorCode.invalidTask, 'prompt must be non-empty after trimming');
  }
  return normalized;
}

/// 合并编辑补丁：触碰规则时整组替换为 patch 里的规则，否则保留原规则。
Map<String, Object?> mergeTaskRules(
  CronTask task,
  String prompt,
  bool touched,
  Map<String, Object?> patch,
) {
  final Map<String, Object?> merged =
      <String, Object?>{'id': task.id, 'prompt': prompt};
  for (final String key in kCronRuleKeys) {
    final Object? value = touched ? patch[key] : cronTaskRuleValue(task, key);
    if (value != null) merged[key] = value;
  }
  return merged;
}

/// 任务在某个规则键下的当前值。
Object? cronTaskRuleValue(CronTask task, String key) => switch (key) {
      'at' => task.at,
      'every' => task.every,
      'daily' => task.daily,
      _ => task.cron,
    };

/// 把校验后的合并结果写回任务记录。
void applyTaskRules(CronTask task, Map<String, Object?> merged) {
  task.prompt = merged['prompt']! as String;
  task.at = merged['at'] as String?;
  task.every = merged['every'] as num?;
  task.daily = merged['daily'] as String?;
  task.cron = merged['cron'] as String?;
}

/// 规则被替换后重置运行状态，让新规则立即生效。
void resetCronRunState(CronTask task) {
  task.lastRunAt = null;
  task.firedAt = null;
  task.cronNext = null;
  final String? cron = task.cron;
  task.cronParsed = cron == null ? null : parseCronExpression(cron);
}

/// 解析 update 的 prompt 补丁：非空字符串胜出，否则保留现状。
String resolveCronPrompt(String current, Object? patchPrompt) {
  final String? text = patchPrompt is String ? patchPrompt.trim() : null;
  return text == null || text.isEmpty ? current : text;
}
