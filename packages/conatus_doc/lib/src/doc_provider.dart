/// provideDoc 装配：文档引擎，服务键 `'doc'`。
library;

import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';

import 'annotation.dart';
import 'doc_events.dart';
import 'doc_patch.dart';
import 'fold.dart';
import 'patch_log.dart';

/// `ctx.doc`：当前上下文可见的 [DocEngine]。
extension DocContext on Context {
  /// 取当前上下文可见的 [DocEngine]（未提供时抛 [StateError]）。
  DocEngine get doc => require<DocEngine>('doc');
}

/// 文档引擎：补丁序列 + 可选的 SessionLog 桥。
///
/// 装配了 SessionLog 与 sessionId 时，每次提交 / 作废 / 截断 / 批注都同步
/// 落 `doc/*` 事件（故事层持久化）；未装配时为纯内存引擎。
class DocEngine {
  /// 以 [log] 与可选的 SessionLog 桥构造。
  ///
  /// [eventIds] 是与 `log.patches` 对齐的会话事件 id 序列（fork 切点映射），
  /// 一般由 [rebuildDocEngine] 重建时填入，日常构造不必传。
  DocEngine(
    this._log, {
    SessionLog? sessionLog,
    String? sessionId,
    List<String?>? eventIds,
  })  : _sessionLog = sessionLog,
        _sessionId = sessionId,
        _eventIds = eventIds ?? <String?>[];

  final PatchLog _log;
  final SessionLog? _sessionLog;
  final String? _sessionId;
  final List<String?> _eventIds;

  /// 底层补丁序列。
  PatchLog get log => _log;

  /// 当前文档状态（生效补丁集的 fold）。
  DocumentState get state => foldPatches(_log.effective());

  /// 提交补丁（追加 + 落事件，并记录事件 id 作为 fork 切点）。
  Future<void> commit(DocPatch patch) async {
    _log.append(patch);
    final SessionEvent? event = await _record(
        (SessionLog log, String sid) => recordDocPatch(log, sid, patch));
    _eventIds.add(event?.id);
  }

  /// 追加锚点批注（追加 + 落事件）。
  Future<void> annotate(DocAnnotation annotation) async {
    _log.annotate(annotation);
    await _record(
      (SessionLog log, String sid) => recordDocAnnotation(log, sid, annotation),
    );
  }

  /// 作废单个补丁（丢弃失锚补丁等场景）。
  Future<void> discard(String patchId) async {
    _log.voidPatch(patchId);
    await _record(
        (SessionLog log, String sid) => recordDocVoid(log, sid, patchId));
  }

  /// 截断：作废 [index] 之后的全部补丁。
  Future<void> truncateAfter(int index) async {
    _log.truncateAfter(index);
    await _record(
      (SessionLog log, String sid) => recordDocTruncate(log, sid, index),
    );
  }

  /// 预览 [upto]（不含）时刻的文档状态。
  DocumentState previewAt(int upto) => foldPatches(_log.effective(upto: upto));

  /// 分叉：从 [upto]（不含）起新故事线。
  ///
  /// 装配了 SessionLog 且切点可得时，同时做**会话层 fork**：切点是第
  /// `upto - 1` 个补丁落定的事件 id，新引擎挂在分叉会话上，后续提交落进
  /// 新会话。切点不可得（纯内存 / 事件 id 缺失）时退化为纯文档层分叉。
  Future<DocEngine> forkAt(int upto, {String? newSessionId}) async {
    final PatchLog branch = _log.forkAt(upto);
    final String? cut = _cutEventId(upto);
    final SessionLog? log = _sessionLog;
    final String? sid = _sessionId;
    if (log == null || sid == null || cut == null) {
      return DocEngine(branch);
    }
    final String forked = await log.fork(sid, cut, newId: newSessionId);
    return DocEngine(
      branch,
      sessionLog: log,
      sessionId: forked,
      eventIds: _eventIds.sublist(0, upto),
    );
  }

  String? _cutEventId(int upto) {
    if (upto <= 0 || upto > _eventIds.length) return null;
    return _eventIds[upto - 1];
  }

  Future<SessionEvent?> _record(
    Future<SessionEvent> Function(SessionLog, String) write,
  ) async {
    final SessionLog? log = _sessionLog;
    final String? sid = _sessionId;
    if (log == null || sid == null) return null;
    return write(log, sid);
  }
}

/// 从会话事件流重建引擎：补丁序列（含批注与作废标记）+ fork 切点映射。
Future<DocEngine> rebuildDocEngine(SessionLog log, String sessionId) async {
  final PatchLog rebuilt = PatchLog();
  final List<String?> eventIds = <String?>[];
  await log.replay(sessionId, (SessionEvent event) {
    if (event.type == kDocPatchEvent) eventIds.add(event.id);
    applyDocEvent(rebuilt, event);
  });
  return DocEngine(
    rebuilt,
    sessionLog: log,
    sessionId: sessionId,
    eventIds: eventIds,
  );
}

/// 提供 [DocEngine] 为 `'doc'` 服务。
///
/// [sessionLog] 缺省时取上下文里的 `'sessionLog'` 服务；两者都没有则为
/// 纯内存引擎（不落事件）。
DocEngine provideDoc(
  Context ctx, {
  String? sessionId,
  SessionLog? sessionLog,
}) {
  final SessionLog? resolved = sessionLog ?? ctx.get<SessionLog>('sessionLog');
  final DocEngine engine = DocEngine(
    PatchLog(),
    sessionLog: resolved,
    sessionId: sessionId,
  );
  ctx.provide('doc', engine);
  return engine;
}
