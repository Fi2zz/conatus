/// checkpoint 的类型：清单（base/delta）、文件条目、恢复计数与异常。
library;

/// 检查点相关错误。
class CheckpointException implements Exception {
  const CheckpointException(this.code, this.message);

  /// 机器可读错误码（`missing-manifest` / `missing-checkpoint` / `missing-base`）。
  final String code;

  /// 人可读说明。
  final String message;

  @override
  String toString() => 'CheckpointException($code): $message';
}

/// base 清单里的一个文件条目：路径 + 变化检测用的 mtime/size + 内容哈希。
class CheckpointFileEntry {
  const CheckpointFileEntry({
    required this.path,
    required this.mtimeMs,
    required this.size,
    this.hash,
  });

  /// 反序列化；兼容旧格式的纯字符串路径（mtime/size/hash 记缺省）。
  factory CheckpointFileEntry.fromJson(Object? raw) {
    if (raw is String) {
      return CheckpointFileEntry(path: raw, mtimeMs: 0, size: 0);
    }
    final Map<String, Object?> json =
        (raw as Map?)?.cast<String, Object?>() ?? const <String, Object?>{};
    return CheckpointFileEntry(
      path: '${json['path'] ?? ''}',
      mtimeMs: json['mtimeMs'] as int? ?? 0,
      size: json['size'] as int? ?? 0,
      hash: json['hash'] as String?,
    );
  }

  /// 相对工作区根的路径。
  final String path;

  /// 快照时刻的修改时间（epoch 毫秒）。
  final int mtimeMs;

  /// 快照时刻的字节数。
  final int size;

  /// 快照时刻的内容 SHA-256（十六进制）；旧条目为 `null`（按变化处理）。
  final String? hash;

  Map<String, Object?> toJson() => <String, Object?>{
        'path': path,
        'mtimeMs': mtimeMs,
        'size': size,
        if (hash != null) 'hash': hash,
      };
}

/// 一个检查点的清单。
///
/// `kind = 'base'`（turn 0）：全量文件 + 各自 mtime/size（变化检测锚点，永不
/// prune）；`kind = 'delta'`（turn > 0）：相对 base 的 `changed`（新增/修改）与
/// `deleted`。旧格式（无 kind 字段）按 base 读，files 为字符串路径。
class CheckpointManifest {
  const CheckpointManifest({
    required this.kind,
    required this.turn,
    this.lastEventId,
    this.files = const <CheckpointFileEntry>[],
    this.changed = const <String>[],
    this.deleted = const <String>[],
  });

  /// 反序列化。
  factory CheckpointManifest.fromJson(Map<String, Object?> json) {
    final bool delta = json['kind'] == 'delta';
    return CheckpointManifest(
      kind: delta ? 'delta' : 'base',
      turn: json['turn'] as int? ?? 0,
      lastEventId: json['lastEventId'] as String?,
      files: <CheckpointFileEntry>[
        for (final Object? item
            in (json['files'] as List<Object?>?) ?? const <Object?>[])
          CheckpointFileEntry.fromJson(item),
      ],
      changed: <String>[
        for (final Object? item
            in (json['changed'] as List<Object?>?) ?? const <Object?>[])
          if (item is String) item,
      ],
      deleted: <String>[
        for (final Object? item
            in (json['deleted'] as List<Object?>?) ?? const <Object?>[])
          if (item is String) item,
      ],
    );
  }

  /// `base`（turn 0 全量）或 `delta`（相对 base 的差量）。
  final String kind;

  /// 快照时的轮次。
  final int turn;

  /// 快照时刻该会话的最后一条事件 id（对话回滚的 fork 切点）。
  final String? lastEventId;

  /// base 全量文件（带 mtime/size）。
  final List<CheckpointFileEntry> files;

  /// delta：相对 base 新增/修改的文件。
  final List<String> changed;

  /// delta：相对 base 删除的文件。
  final List<String> deleted;

  /// 是否为差量清单。
  bool get isDelta => kind == 'delta';

  /// 序列化。
  Map<String, Object?> toJson() => <String, Object?>{
        'kind': kind,
        'turn': turn,
        if (lastEventId != null) 'lastEventId': lastEventId,
        if (isDelta)
          'changed': changed
        else
          'files': <Map<String, Object?>>[
            for (final CheckpointFileEntry entry in files) entry.toJson(),
          ],
        if (isDelta && deleted.isNotEmpty) 'deleted': deleted,
      };
}

/// 一次恢复的结果计数。
class CheckpointRestore {
  const CheckpointRestore({required this.restored, required this.deleted});

  /// 覆盖/补回的文件数。
  final int restored;

  /// 删除的（当前有、目标状态没有的）文件数。
  final int deleted;
}

/// 一个可用检查点的摘要（`/rewind list` 展示用）。
class CheckpointInfo {
  const CheckpointInfo({required this.turn, required this.files});

  /// 轮次。
  final int turn;

  /// 该检查点的有效文件数（base 全量 / delta 合成）。
  final int files;
}

/// 一次回滚的结果：目标轮次 + 恢复计数 + 对话切点事件 id。
class CheckpointRewindResult {
  const CheckpointRewindResult({
    required this.turn,
    required this.restore,
    this.lastEventId,
  });

  /// 实际回滚到的轮次。
  final int turn;

  /// 恢复计数。
  final CheckpointRestore restore;

  /// 目标检查点的 [CheckpointManifest.lastEventId]（对话 fork 切点）。
  final String? lastEventId;
}
