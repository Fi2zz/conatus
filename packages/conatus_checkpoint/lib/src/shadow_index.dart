/// 影子仓库的会话索引：轮次 → 提交 sha 与该轮的有效文件数。
///
/// 与归档实现的 `index`（gzip JSON，`turn → files`）同形但多带一个提交
/// sha——影子实现的「清单」就是那个 commit，故索引是 turn 到 commit 的唯一
/// 映射。`lastEventId` 也存这里（对话 fork 的切点）。
///
/// 单独成文件而非塞进 [CheckpointStore]：这是影子实现专属的索引格式，
/// 归档实现的读法（`readCheckpointIndex`）不适用也不该复用。
library;

import 'dart:convert';
import 'dart:io';

import 'checkpoint_types.dart';

/// 某一轮的检查点定位信息。
class ShadowCheckpointRef {
  const ShadowCheckpointRef({
    required this.turn,
    required this.commit,
    required this.files,
    this.lastEventId,
  });

  /// 轮次（0 = 基线）。
  final int turn;

  /// 该轮对应的 git 提交 sha。
  final String commit;

  /// 该轮状态下的有效文件数（`git ls-tree` 计数，供 `/rewind list` 展示）。
  final int files;

  /// 快照时刻会话的最后一条事件 id。
  final String? lastEventId;

  /// 转成清单形状，供 [CheckpointManager.rewind] 读对话切点。
  ///
  /// `files` 留空：影子实现的文件清单在 git 树里（`ls-tree`），不在这儿
  /// 物化。展示用的文件数走 [files] 字段与 `CheckpointStore.list`。
  CheckpointManifest toManifest() => CheckpointManifest(
        kind: turn == 0 ? 'base' : 'delta',
        turn: turn,
        lastEventId: lastEventId,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'turn': turn,
        'commit': commit,
        'files': files,
        if (lastEventId != null) 'lastEventId': lastEventId,
      };

  static ShadowCheckpointRef? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final Object? commit = raw['commit'];
    if (commit is! String || commit.isEmpty) return null;
    return ShadowCheckpointRef(
      turn: raw['turn'] as int? ?? 0,
      commit: commit,
      files: raw['files'] as int? ?? 0,
      lastEventId: raw['lastEventId'] as String?,
    );
  }
}

/// 读影子索引；不存在或损坏返回空列表。
List<ShadowCheckpointRef> readShadowIndex(File file) {
  if (!file.existsSync()) return const <ShadowCheckpointRef>[];
  try {
    final Map<String, Object?> json =
        jsonDecode(utf8.decode(gzip.decode(file.readAsBytesSync())))
            as Map<String, Object?>;
    return <ShadowCheckpointRef>[
      for (final Object? item
          in (json['turns'] as List<Object?>?) ?? const <Object?>[])
        if (ShadowCheckpointRef.fromJson(item) case final ShadowCheckpointRef r)
          r,
    ]..sort(
        (ShadowCheckpointRef a, ShadowCheckpointRef b) =>
            a.turn.compareTo(b.turn),
      );
  } catch (_) {
    return const <ShadowCheckpointRef>[];
  }
}

/// 写影子索引（gzip JSON，按轮次升序）。
void writeShadowIndex(File file, List<ShadowCheckpointRef> refs) {
  file.parent.createSync(recursive: true);
  final List<ShadowCheckpointRef> sorted = <ShadowCheckpointRef>[...refs]..sort(
      (ShadowCheckpointRef a, ShadowCheckpointRef b) =>
          a.turn.compareTo(b.turn),
    );
  file.writeAsBytesSync(
    gzip.encode(
      utf8.encode(
        jsonEncode(<String, Object?>{
          'turns': <Map<String, Object?>>[
            for (final ShadowCheckpointRef ref in sorted) ref.toJson(),
          ],
        }),
      ),
    ),
  );
}
