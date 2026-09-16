/// 一次到期交付：渲染 framing、投递，并只在入队成功后才写入派发记录。
///
/// 顺序属于协议：**先构造完整 framing，再投递，投递成功后才追加 dispatch**。
/// framing 或投递失败不写任何记录（记录保持活动，等下一次触发）；dispatch 写入
/// 失败必须向上报告为故障，因为消息可能已经入队、不能重发。
library;

import 'schedule.dart';
import 'schedule_due.dart';
import 'schedule_errors.dart';
import 'schedule_framing.dart';
import 'schedule_types.dart';

/// 交付端口：把 framing 文本投递进会话，返回是否成功入队。
///
/// 返回 `false` 表示当前无法投递（例如会话正在回答），记录保持活动并在下一次
/// 触发时重试。
typedef ScheduleDelivery = Future<bool> Function(String text);

/// 一次交付的结局。
enum ScheduleDeliveryOutcome {
  /// framing 已投递、派发记录已写入，且落盘检查点通过。
  dispatched,

  /// 未发生投递或投递被拒绝：不写派发记录，记录保持活动。
  deferred,

  /// 投递抛错：不写派发记录，记录保持活动。
  failed,

  /// 派发记录写入失败：消息可能已经入队，调用方必须停止派发。
  faulted,

  /// 派发记录已写入，但落盘检查点未能确认。
  uncertain,
}

/// 交付一次到期决策，并返回其结局。
Future<ScheduleDeliveryOutcome> deliverDueDecision({
  required DueDecision decision,
  required SessionSchedule schedule,
  required ScheduleDelivery deliver,
  void Function(String message)? onWarning,
}) async {
  final String text = renderDueFraming(decision);
  if (text.isEmpty) return ScheduleDeliveryOutcome.deferred;
  final bool queued;
  try {
    queued = await deliver(text);
  } on Object catch (error) {
    warnSchedule(onWarning, 'schedule: delivery failed: $error');
    return ScheduleDeliveryOutcome.failed;
  }
  if (!queued) return ScheduleDeliveryOutcome.deferred;
  try {
    recordScheduleDispatch(decision, schedule);
  } on Object catch (error) {
    warnSchedule(onWarning, 'schedule: dispatch append failed: $error');
    return ScheduleDeliveryOutcome.faulted;
  }
  try {
    await schedule.checkpoint(ScheduleOperation.list);
  } on Object catch (error) {
    warnSchedule(onWarning, 'schedule: dispatch barrier failed: $error');
    return ScheduleDeliveryOutcome.uncertain;
  }
  return ScheduleDeliveryOutcome.dispatched;
}

/// 把一次已投递的决策写入派发历史；固定间隔批次共用同一个决策时点。
void recordScheduleDispatch(DueDecision decision, SessionSchedule schedule) {
  switch (decision) {
    case ScheduleOneShotDue(:final ScheduleRecord record):
      schedule.recordDispatch(record.id);
    case ScheduleEveryBatchDue(
        :final List<ScheduleDue> reminders,
        :final DateTime acceptedAt
      ):
      for (final ScheduleDue due in reminders) {
        schedule.recordDispatch(due.record.id, acceptedAt: acceptedAt);
      }
    case ScheduleWait():
      return;
  }
}

/// 向可选的告警回调报告一次可容错失败。
void warnSchedule(void Function(String message)? handler, String message) {
  if (handler != null) handler(message);
}
