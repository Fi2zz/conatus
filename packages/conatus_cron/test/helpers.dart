/// cron 测试共享夹具：假时钟锚点、任务构造、临时存储服务、运行时 harness 与
/// 工具装配。本文件不是 `*_test.dart`，`dart test` 不会把它当测试跑，只被
/// 各测试文件 import。
library;

import 'dart:io';

import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_cron/conatus_cron.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

/// 共享的假时钟锚点（2026-09-16 10:00 本地）。
final DateTime base = DateTime(2026, 9, 16, 10);

/// 构造一个规则任务（解析 cron 表达式并装好缓存）。
CronTask buildTask({
  String id = 'demo',
  String? at,
  num? every,
  String? daily,
  String? cron,
  bool enabled = true,
}) {
  final CronTask task = CronTask(
    id: id,
    prompt: 'ping',
    at: at,
    every: every,
    daily: daily,
    cron: cron,
    enabled: enabled,
    origin: CronTaskOrigin.dynamic,
  );
  task.cronParsed = cron == null ? null : parseCronExpression(cron);
  return task;
}

/// 本地时刻的毫秒数（跨时区稳定比较）。
int epoch(DateTime local) => local.millisecondsSinceEpoch;

/// 临时存储 + 服务（告警收集到 [warnings]）。
({
  CronService service,
  CronStorage storage,
  Directory dir,
  List<String> warnings
}) buildService({
  List<Map<String, Object?>> configTasks = const <Map<String, Object?>>[],
  DateTime Function()? clock,
}) {
  final Directory dir =
      Directory.systemTemp.createTempSync('conatus-cron-test-');
  addTearDown(() => dir.deleteSync(recursive: true));
  final List<String> warnings = <String>[];
  final CronStorage storage = JsonCronStorage(
    tasksPath: '${dir.path}/cron-tasks.json',
    historyPath: '${dir.path}/cron-history.jsonl',
    onWarning: warnings.add,
  );
  final CronService service = CronService(
    storage: storage,
    configTasks: configTasks,
    clock: clock ?? () => base,
    onWarning: warnings.add,
  );
  return (service: service, storage: storage, dir: dir, warnings: warnings);
}

/// 直接交付一次任务（绕过运行时）。
CronRunRecord fireOnce(CronService service, String taskId, DateTime at) {
  final CronRecordRef ref = service.allocateRecordRef(at);
  return service.commitFire(ref: ref, taskId: taskId, slot: at, firedAt: at);
}

/// 运行时测试夹具：假时钟、临时存储、服务与投递/告警记录。
class Harness {
  Harness({DateTime Function()? clock, bool Function(String framing)? deliver})
      : warnings = <String>[],
        delivered = <String>[],
        records = <String>[],
        tasks = <CronTask>[],
        _deliver = deliver {
    final Directory dir =
        Directory.systemTemp.createTempSync('conatus-cron-runtime-');
    addTearDown(() => dir.deleteSync(recursive: true));
    storage = JsonCronStorage(
      tasksPath: '${dir.path}/cron-tasks.json',
      historyPath: '${dir.path}/cron-history.jsonl',
    );
    service = CronService(
      storage: storage,
      clock: clock ?? () => base,
      onWarning: warnings.add,
    );
  }

  late final CronStorage storage;
  late final CronService service;
  final List<String> warnings;
  final List<String> delivered;
  final List<String> records;
  final List<CronTask> tasks;
  final bool Function(String framing)? _deliver;

  Future<bool> accept(String recordId, String framing, CronTask task) async {
    delivered.add(framing);
    records.add(recordId);
    tasks.add(task);
    final bool Function(String framing)? custom = _deliver;
    return custom == null ? true : custom(framing);
  }
}

/// 工具测试装配：上下文 + 五个工具 + cron 服务（假时钟）。
({Context ctx, CronService service}) buildTools({
  List<Map<String, Object?>> configTasks = const <Map<String, Object?>>[],
}) {
  final Context ctx = Context.root();
  addTearDown(ctx.dispose);
  final Directory dir =
      Directory.systemTemp.createTempSync('conatus-cron-tools-');
  addTearDown(() => dir.deleteSync(recursive: true));
  final CronStorage storage = JsonCronStorage(
    tasksPath: '${dir.path}/cron-tasks.json',
    historyPath: '${dir.path}/cron-history.jsonl',
  );
  provideTools(ctx);
  final CronService service = provideCron(
    ctx,
    storage: storage,
    configTasks: configTasks,
    clock: () => base,
  );
  provideCronTools(ctx);
  return (ctx: ctx, service: service);
}

/// 通过注册表调用一个工具。
Future<ToolResult> call(Context ctx, String name,
        [Map<String, Object?> arguments = const <String, Object?>{}]) =>
    ctx.tools.call(ToolCall(name: name, arguments: arguments));
