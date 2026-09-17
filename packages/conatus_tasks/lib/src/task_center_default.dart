/// task 插件的默认实现。
///
/// [DefaultTaskCenter] 把任务状态接到三个能力缝上：`session` 持久化
/// `task/changed` 事件（整值替换，恢复时按 id 折叠最后一个）、`approval`
/// shell 类任务取消确认（缺省自动批准）、`telemetry` 埋点（`task.*` 事件）。
/// 全部可选，缺省时降级（内存状态 / 自动批准 / 无埋点）。
library;

import 'dart:async';

import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'task.dart';
import 'task_center.dart';

/// [TaskCenter] 的默认实现：内存任务表 + 可选 Session 持久化。
class DefaultTaskCenter implements TaskCenter {
  /// 各 seam 显式传入优先；缺省时从 [ctx] 惰性解析；再缺省则降级。
  /// 提供 [session]（或上下文可解析出 `session`）时构造即自动恢复。
  DefaultTaskCenter({
    Session? session,
    Approval? approval,
    Telemetry? telemetry,
    Context? ctx,
  })  : _session = session,
        _approval = approval,
        _telemetry = telemetry,
        _ctx = ctx {
    final Session? resolved = resolveSession();
    if (resolved != null) restore(resolved);
  }

  final Context? _ctx;
  Session? _session;
  Approval? _approval;
  Telemetry? _telemetry;
  final Map<String, Task> _tasks = <String, Task>{};
  final Map<String, Future<void> Function()> _cancellers =
      <String, Future<void> Function()>{};
  final StreamController<Task> _changes = StreamController<Task>.broadcast();
  int _seq = 0;
  bool _disposed = false;

  /// 解析 session（显式 > 上下文服务），首次解析后缓存。
  Session? resolveSession() => _session ??= _ctx?.get<Session>('session');

  @override
  Stream<Task> get changes => _changes.stream;

  Approval? _resolveApproval() => _approval ??= _ctx?.get<Approval>('approval');

  Telemetry? _resolveTelemetry() =>
      _telemetry ??= _ctx?.get<Telemetry>('telemetry');

  @override
  Future<Task> create({
    required TaskKind kind,
    required String description,
    String? parentTaskId,
    Map<String, Object?>? metadata,
  }) async {
    _ensureOpen();
    _seq++;
    final Task task = Task(
      id: 'task-$_seq-${DateTime.now().microsecondsSinceEpoch}',
      kind: kind,
      status: TaskStatus.pending,
      description: description,
      createdAt: DateTime.now(),
      parentTaskId: parentTaskId,
      metadata: metadata ?? const <String, Object?>{},
    );
    _tasks[task.id] = task;
    _persist(task);
    _emit('task.created', task);
    _changes.add(task);
    return task;
  }

  @override
  Future<Task> update(
    String id, {
    TaskStatus? status,
    Object? result,
    Object? error,
  }) async {
    _ensureOpen();
    final Task? existing = _tasks[id];
    if (existing == null) throw TaskException('not-found', '任务 $id 不存在');
    if (existing.isTerminal) {
      throw TaskException('already-terminal', '任务 $id 已结束');
    }
    final DateTime now = DateTime.now();
    Task updated = existing;
    if (status == TaskStatus.running && existing.startedAt == null) {
      updated = updated.copyWith(startedAt: now);
    }
    if (status != null && status != existing.status) {
      updated = updated.copyWith(status: status);
      if (updated.isTerminal) updated = updated.copyWith(finishedAt: now);
    }
    if (result != null) updated = updated.copyWith(result: result);
    if (error != null) updated = updated.copyWith(error: error);
    if (identical(updated, existing)) return existing;
    _tasks[id] = updated;
    _persist(updated);
    _emitTransition(existing, updated);
    _changes.add(updated);
    return updated;
  }

  @override
  Task? get(String id) => _tasks[id];

  @override
  List<Task> get all => List<Task>.unmodifiable(_tasks.values);

  @override
  List<Task> get active => <Task>[
        for (final Task t in _tasks.values)
          if (t.isActive) t
      ];

  @override
  List<Task> childrenOf(String parentId) => <Task>[
        for (final Task task in _tasks.values)
          if (task.parentTaskId == parentId) task,
      ];

  @override
  List<Task> subtreeOf(String id) {
    final List<Task> result = <Task>[];
    final List<String> frontier = <String>[id];
    while (frontier.isNotEmpty) {
      final String current = frontier.removeLast();
      final Task? task = _tasks[current];
      if (task != null) result.add(task);
      frontier.addAll(childrenOf(current).map((Task t) => t.id));
    }
    return result;
  }

  @override
  Future<void> cancel(String id) async {
    _ensureOpen();
    final Task? task = _tasks[id];
    if (task == null) throw TaskException('not-found', '任务 $id 不存在');
    if (task.isTerminal) {
      throw TaskException('already-terminal', '任务 $id 已结束');
    }
    await _confirmCancel(task);
    await cancelChildren(id);
    final Future<void> Function()? canceller = _cancellers.remove(id);
    if (canceller != null) await canceller();
    final Task cancelled = task.copyWith(
      status: TaskStatus.cancelled,
      finishedAt: DateTime.now(),
    );
    _tasks[id] = cancelled;
    _persist(cancelled);
    _emit('task.cancelled', cancelled);
    _changes.add(cancelled);
  }

  @override
  Future<void> cancelChildren(String id) async {
    for (final Task child in childrenOf(id)) {
      if (!child.isActive) continue;
      await cancel(child.id);
    }
  }

  @override
  void registerCancel(String id, Future<void> Function() canceller) {
    _cancellers[id] = canceller;
  }

  @override
  void restore(Session session) {
    _session = session;
    _tasks
      ..clear()
      ..addAll(restoreTaskState(session));
    for (final Task task in List<Task>.of(_tasks.values)) {
      if (!task.isActive) continue;
      final Task stale = task.copyWith(
        status: TaskStatus.failed,
        error: kTaskStaleReason,
        finishedAt: DateTime.now(),
      );
      _tasks[task.id] = stale;
      _persist(stale);
      _emit('task.failed', stale);
      _changes.add(stale);
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _cancellers.clear();
    unawaited(_changes.close());
  }

  void _ensureOpen() {
    if (_disposed) {
      throw const TaskException('disposed', '任务中心已释放');
    }
  }

  void _persist(Task task) =>
      resolveSession()?.append(kTaskEvent, data: task.toJson());

  void _emit(String name, Task task) =>
      _resolveTelemetry()?.emit(TelemetryEvent(name, data: <String, Object?>{
        'id': task.id,
        'kind': task.kind.name,
        'status': task.status.name,
        'description': task.description,
      }));

  void _emitTransition(Task previous, Task current) {
    final String? event = switch ((previous.status, current.status)) {
      (TaskStatus.pending, TaskStatus.running) => 'task.started',
      (TaskStatus.paused, TaskStatus.running) => 'task.resumed',
      (TaskStatus.running, TaskStatus.paused) => 'task.paused',
      (_, TaskStatus.completed) => 'task.completed',
      (_, TaskStatus.failed) => 'task.failed',
      _ => null,
    };
    if (event != null) _emit(event, current);
  }

  Future<void> _confirmCancel(Task task) async {
    final Approval? approval = _resolveApproval();
    if (approval == null || task.kind != TaskKind.shell) return;
    final bool ok = await approval.request(ApprovalRequest(
      id: 'cancel-${task.id}',
      toolName: 'cancel_task',
      arguments: <String, Object?>{
        'id': task.id,
        'description': task.description
      },
      description: '取消任务「${task.description}」？',
    ));
    if (!ok) throw const TaskException('cancelled', '用户取消');
  }
}
