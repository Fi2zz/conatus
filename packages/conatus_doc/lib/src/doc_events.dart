/// SessionLog 桥：补丁提交即事件，故事层落到会话日志。
///
/// 人的编辑与 AI 的补丁在这里同权：都是 `doc/patch` 事件进 log（设计文档
/// §2.4「人的编辑是一等事件」）。
library;

import 'package:conatus_foundation/conatus_foundation.dart';

import 'annotation.dart';
import 'doc_patch.dart';
import 'patch_log.dart';

/// 补丁提交事件类型。
const String kDocPatchEvent = 'doc/patch';

/// 补丁作废事件类型（截断 / 丢弃）。
const String kDocVoidEvent = 'doc/void';

/// 补丁截断事件类型（`after` 之后全部作废）。
const String kDocTruncateEvent = 'doc/truncate';

/// 锚点批注事件类型。
const String kDocAnnotationEvent = 'doc/annotation';

/// 把补丁提交追加为 `doc/patch` 事件，返回落定后的事件。
Future<SessionEvent> recordDocPatch(
  SessionLog log,
  String sessionId,
  DocPatch patch,
) =>
    log.append(
      SessionEvent.create(
        sessionId: sessionId,
        type: kDocPatchEvent,
        seq: 0,
        data: patch.toJson(),
      ),
    );

/// 记录单个补丁作废。
Future<SessionEvent> recordDocVoid(
  SessionLog log,
  String sessionId,
  String patchId,
) =>
    log.append(
      SessionEvent.create(
        sessionId: sessionId,
        type: kDocVoidEvent,
        seq: 0,
        data: <String, Object?>{'patchId': patchId},
      ),
    );

/// 记录截断：[after] 下标之后的补丁全部作废。
Future<SessionEvent> recordDocTruncate(
  SessionLog log,
  String sessionId,
  int after,
) =>
    log.append(
      SessionEvent.create(
        sessionId: sessionId,
        type: kDocTruncateEvent,
        seq: 0,
        data: <String, Object?>{'after': after},
      ),
    );

/// 记录一条锚点批注。
Future<SessionEvent> recordDocAnnotation(
  SessionLog log,
  String sessionId,
  DocAnnotation annotation,
) =>
    log.append(
      SessionEvent.create(
        sessionId: sessionId,
        type: kDocAnnotationEvent,
        seq: 0,
        data: annotation.toJson(),
      ),
    );

/// 把一条事件应用回 [log]（replay / 重建用）；非 doc 事件忽略。
void applyDocEvent(PatchLog log, SessionEvent event) {
  final Object? data = event.data;
  if (data is! Map) return;
  final void Function(PatchLog, Map<String, Object?>)? applier =
      _eventAppliers[event.type];
  if (applier == null) return;
  applier(log, Map<String, Object?>.from(data));
}

/// 从会话事件流重建补丁序列（含批注与作废标记）。
Future<PatchLog> rebuildPatchLog(SessionLog log, String sessionId) async {
  final PatchLog rebuilt = PatchLog();
  await log.replay(
    sessionId,
    (SessionEvent event) => applyDocEvent(rebuilt, event),
  );
  return rebuilt;
}

const Map<String, void Function(PatchLog, Map<String, Object?>)>
    _eventAppliers = <String, void Function(PatchLog, Map<String, Object?>)>{
  kDocPatchEvent: _applyPatch,
  kDocVoidEvent: _applyVoid,
  kDocTruncateEvent: _applyTruncate,
  kDocAnnotationEvent: _applyAnnotation,
};

void _applyPatch(PatchLog log, Map<String, Object?> data) =>
    log.append(DocPatch.fromJson(data));

void _applyVoid(PatchLog log, Map<String, Object?> data) =>
    log.voidPatch(data['patchId'] as String);

void _applyTruncate(PatchLog log, Map<String, Object?> data) =>
    log.truncateAfter(data['after'] as int);

void _applyAnnotation(PatchLog log, Map<String, Object?> data) =>
    log.annotate(DocAnnotation.fromJson(data));
