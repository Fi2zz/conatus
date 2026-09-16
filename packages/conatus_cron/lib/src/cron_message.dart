/// 任务呈现：模型可见视图构造与触发 framing 渲染。
///
/// framing 逐行与 dsh-cron 保持一致——它明确告知模型这是自动化任务而非用户
/// 输入，是防注入设计的一部分，不许改写。
library;

import 'cron_rules.dart';
import 'cron_types.dart';

/// 由内部记录与单次墙钟采样构造模型可见视图。
CronTaskView buildTaskView(CronTask task, DateTime now, DateTime startedAt) =>
    CronTaskView(
      id: task.id,
      prompt: task.prompt,
      schedule: _scheduleJson(task),
      enabled: taskEnabled(task),
      origin: task.origin,
      sessionId: task.sessionId,
      lastRunAt: task.lastRunAt,
      firedAt: task.firedAt,
      nextRunAt: nextRunAtOf(task, now, startedAt),
    );

Map<String, Object?> _scheduleJson(CronTask task) {
  if (task.at != null) return <String, Object?>{'at': task.at};
  if (task.every != null) return <String, Object?>{'everySeconds': task.every};
  if (task.daily != null) return <String, Object?>{'daily': task.daily};
  return <String, Object?>{'cron': task.cron};
}

/// 触发消息 framing；动态字段是 id 与时刻，任务原文原样包在 `<task>` 内。
String renderTaskMessage({
  required String id,
  required String prompt,
  required DateTime slot,
  required DateTime firedAt,
}) =>
    <String>[
      '[cron] Scheduled task "$id" fired.',
      'Scheduled for: ${formatCronInstant(slot)}',
      'Fired at: ${formatCronInstant(firedAt)}',
      '',
      'This is an automated task submitted by the cron plugin, '
          'not a message from the user.',
      'Execute the task inside <task> now, then report the result concisely.',
      '',
      '<task>',
      prompt,
      '</task>',
    ].join('\n');
