/// 归档式工作区快照存储：每个检查点 = 单个不可读名的 gzip 归档文件。
///
/// 布局：`<projectDir>/checkpoints/<sessionId>/<sha256前16位>`（文件名是
/// 确定性哈希，**不可读、不暴露轮次**；轮次只记录在归档头部与会话级 `index`
/// 里）+ `index`（gzip 小索引：turn → 有效文件数，`list`/`prune` 只读它）。
/// turn 0 全量 base + 各轮相对 base 差量；base 永不 prune，prune 只裁差量、
/// 保留最近 `keep - 1` 个。旧版目录树检查点（`<turn>/` 可读名）读时兼容，
/// 索引缺失时按旧格式重建。恢复见 `checkpoint_restore.dart`。
///
/// 零外部依赖（只用 `dart:io` 与 `crypto`），任何环境可跑。代价是容器格式
/// 要自己维护，且同一文件的每个版本各存一份完整内容（无跨版本去重）。
///
// REASON: 单一协议实现（快照 / 索引 / 裁剪 / 兼容旧格式）共享私有状态，
// 按行数拆分需把索引与归档命名的内部契约暴露出去，回归风险更大。
library;

import 'dart:convert';
import 'dart:io';

import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:crypto/crypto.dart';

import 'checkpoint_archive.dart';
import 'checkpoint_changes.dart';
import 'checkpoint_hashes.dart';
import 'checkpoint_io.dart';
import 'checkpoint_lookup.dart';
import 'checkpoint_paths.dart';
import 'checkpoint_policy.dart';
import 'checkpoint_restore.dart';
import 'checkpoint_scan.dart';
import 'checkpoint_store.dart';
import 'checkpoint_turn_diff.dart';
import 'checkpoint_types.dart';

/// 归档式快照存储（[CheckpointStore] 的自研 gzip 归档实现）。
class ArchiveCheckpointStore implements CheckpointStore {
  ArchiveCheckpointStore({
    required String root,
    required this.projectDir,
    this.keep = 5,
    this.policy = const CheckpointPolicy(),
  }) : root = Directory(root).absolute.path;

  @override
  final String root;

  @override
  final String projectDir;

  @override
  final int keep;

  @override
  final CheckpointPolicy policy;

  @override
  List<String> get ignore => policy.ignore;

  /// 某会话的检查点目录。
  Directory sessionDir(String sessionId) => Directory(
        '$projectDir${Platform.pathSeparator}checkpoints'
        '${Platform.pathSeparator}$sessionId',
      );

  /// 清空某会话的全部检查点（重绑即新时间线：旧 base/差量一并移除，
  /// 避免「新 base + 旧 delta」合成从未存在过的混合状态）。
  @override
  Future<void> clearSession(String sessionId) async {
    final Directory dir = sessionDir(sessionId);
    if (dir.existsSync()) await dir.delete(recursive: true);
  }

  /// 某检查点的归档文件（不可读哈希名）。
  File archiveFile(String sessionId, int turn) => File(
        '${sessionDir(sessionId).path}${Platform.pathSeparator}'
        '${checkpointArchiveName(sessionId, turn)}',
      );

  /// 会话检查点索引文件。
  File indexFile(String sessionId) =>
      File('${sessionDir(sessionId).path}${Platform.pathSeparator}index');

  /// 某检查点的旧版目录（格式迁移前；不存在返回 `null`）。
  Directory? legacyDir(String sessionId, int turn) {
    final Directory dir = Directory(
      '${sessionDir(sessionId).path}'
      '${Platform.pathSeparator}$turn',
    );
    return dir.existsSync() ? dir : null;
  }

  /// 快照当前工作区为 [turn] 轮（turn 0 全量 base，其余相对 base 差量）。
  ///
  /// 另提供 [snapshotUnindexed] 供基准测量用（写到临时目录、不动索引）。
  @override
  Future<void> snapshot(String sessionId, int turn, {String? lastEventId}) =>
      _snapshot(
        archiveFile(sessionId, turn),
        sessionId,
        turn,
        indexTurn: turn,
        lastEventId: lastEventId,
      );

  /// 快照到指定归档文件（覆盖），**不**动索引与裁剪。
  ///
  /// 供基准测量在临时目录里跑同一份实现；生产路径用 [snapshot]。
  Future<void> snapshotUnindexed(
    File target,
    String sessionId,
    int turn, {
    String? lastEventId,
  }) =>
      _snapshot(target, sessionId, turn, lastEventId: lastEventId);

  Future<void> _snapshot(
    File target,
    String sessionId,
    int turn, {
    int? indexTurn,
    String? lastEventId,
  }) async {
    final CheckpointInfo files;
    if (turn == 0) {
      files = await _snapshotBase(sessionId, target, lastEventId);
    } else {
      files = await _snapshotDelta(sessionId, turn, target, lastEventId);
    }
    if (indexTurn == null) return; // 基准路径：不写索引、不裁剪
    // 清掉同轮的旧版目录（格式迁移）。
    legacyDir(sessionId, indexTurn)?.deleteSync(recursive: true);
    _upsertIndex(sessionId, files);
    await _restrictArtifacts(sessionId, target);
    prune(sessionId);
  }

  /// 收紧会话检查点落盘权限（E-12）：目录 0700 挡遍历、归档 / index / 哈希
  /// 600 兜底。检查点含工作区全文（可能夹带密钥），此前随 umask 0644 落盘。
  Future<void> _restrictArtifacts(String sessionId, File archive) async {
    for (final File file in <File>[
      archive,
      indexFile(sessionId),
      checkpointHashesFile(archive),
    ]) {
      if (file.existsSync()) await restrictFilePermissions(file.path);
    }
    await restrictDirectoryPermissions(sessionDir(sessionId).path);
    // 父目录（checkpoints）也收紧：否则其他用户能遍历列出会话 id 列表。
    await restrictDirectoryPermissions(sessionDir(sessionId).parent.path);
  }

  Future<CheckpointInfo> _snapshotBase(
    String sessionId,
    File target,
    String? lastEventId,
  ) async {
    // 两遍式，但工作区**内容只读一遍**（旧实现读了两遍：pass 1 为算哈希、
    // pass 2 为写内容，882MB 就是 1.76GB 的读）：
    //   pass 1：只 stat，收集 path/mtime/size 写清单头——不需要读内容；
    //   pass 2：流式写内容，同一遍里顺带算 sha256，落 <归档>.hashes 旁挂文件。
    // 清单先行是容器格式约束（gzip 不可回填头部），故两遍结构保留。
    final List<CheckpointFileEntry> entries = await _scanStats();
    final CheckpointArchiveWriter writer = CheckpointArchiveWriter(
      target,
      CheckpointManifest(
        kind: 'base',
        turn: 0,
        lastEventId: lastEventId,
        files: entries,
      ),
      collectHashes: true,
    );
    await for (final FileSystemEntity entity in _walk()) {
      await writer.addFile(checkpointRelativeTo(entity, root), entity as File);
    }
    await writer.close();
    writeCheckpointHashes(target, writer.hashes);
    return CheckpointInfo(turn: 0, files: entries.length);
  }

  Future<CheckpointInfo> _snapshotDelta(
    String sessionId,
    int turn,
    File target,
    String? lastEventId,
  ) async {
    final CheckpointManifest base = await loadManifest(sessionId, 0);
    final Map<String, CheckpointFileEntry> baseStats =
        <String, CheckpointFileEntry>{
      for (final CheckpointFileEntry entry in base.files) entry.path: entry,
    };
    // 基线内容哈希在旁挂文件里（旧检查点 / 手删则无 → 退化为纯 stat 比较）。
    final Map<String, String>? baseHashes = readCheckpointHashes(
      archiveFile(sessionId, 0),
    );
    // pass 1：walk 分类（stat 变化直接记 changed；stat 未变的哈希兜底
    // 「mtime+size 同内容变」），得到完整 changed/deleted 才能写清单头。
    final _DeltaScan scan = await _scanDelta(baseStats, baseHashes);
    final List<String> changed = scan.changed;
    final Set<String> current = scan.current;
    final List<String> deleted = <String>[
      for (final String path in baseStats.keys)
        if (!current.contains(path)) path,
    ];
    // pass 2：把 changed 文件流式写进归档。
    final CheckpointArchiveWriter writer = CheckpointArchiveWriter(
      target,
      CheckpointManifest(
        kind: 'delta',
        turn: turn,
        lastEventId: lastEventId,
        changed: changed,
        deleted: deleted,
      ),
    );
    for (final String rel in changed) {
      await writer.addFile(rel, File('$root${Platform.pathSeparator}$rel'));
    }
    await writer.close();
    final Set<String> basePaths = baseStats.keys.toSet();
    final Set<String> deletedSet = deleted.toSet();
    final int files =
        basePaths.where((String p) => !deletedSet.contains(p)).length +
            changed.where((String p) => !basePaths.contains(p)).length;
    return CheckpointInfo(turn: turn, files: files);
  }

  /// 差量 pass 1：按基线锚点把当前工作区分类为 changed / 全量现存路径。
  ///
  /// 读内容的次数取决于 [baseHashes]：stat 变化即判定、无需哈希；只有
  /// 「mtime+size 未变」的文件才读内容比对哈希。
  Future<_DeltaScan> _scanDelta(
    Map<String, CheckpointFileEntry> baseStats,
    Map<String, String>? baseHashes,
  ) async {
    final List<String> changed = <String>[];
    final Set<String> current = <String>{};
    await for (final FileSystemEntity entity in _walk()) {
      final String rel = checkpointRelativeTo(entity, root);
      current.add(rel);
      final CheckpointFileEntry? old = baseStats[rel];
      if (old == null || _statMoved(old, entity.statSync())) {
        changed.add(rel);
        continue;
      }
      if (await _contentMoved(rel, baseHashes, entity as File)) {
        changed.add(rel);
      }
    }
    return _DeltaScan(changed: changed, current: current);
  }

  /// mtime 或大小相对基线锚点有变动。
  static bool _statMoved(CheckpointFileEntry old, FileStat now) =>
      old.size != now.size ||
      old.mtimeMs != now.modified.millisecondsSinceEpoch;

  /// 「stat 未变但内容变了」的兜底判定。
  ///
  /// 无基线哈希时（旧检查点 / 旁挂文件缺失或损坏）返回 `true`——保守按变化
  /// 处理，与旧实现「`hash == null` 即记 changed」一致。多记进差量只是让
  /// 差量虚胖（回滚仍正确）；漏记则会让 rewind 恢复出陈旧内容。
  static Future<bool> _contentMoved(
    String rel,
    Map<String, String>? baseHashes,
    File file,
  ) async {
    final String? known = baseHashes?[rel];
    if (known == null) return true;
    return known != await _sha256File(file);
  }

  /// 流式列出工作区内需快照的文件（排除目录树、跟随链接关闭）。
  Stream<FileSystemEntity> _walk() => checkpointWalk(root, projectRel, policy);

  /// pass 1 用：全部条目的 stat（不读内容——哈希在 pass 2 顺带产出）。
  Future<List<CheckpointFileEntry>> _scanStats() async {
    final List<CheckpointFileEntry> entries = <CheckpointFileEntry>[];
    await for (final FileSystemEntity entity in _walk()) {
      final FileStat stat = entity.statSync();
      entries.add(
        CheckpointFileEntry(
          path: checkpointRelativeTo(entity, root),
          mtimeMs: stat.modified.millisecondsSinceEpoch,
          size: stat.size,
        ),
      );
    }
    return entries;
  }

  /// 读某检查点的清单（新归档头部；旧版目录清单自动回退）；缺失抛异常。
  ///
  /// 同步版本：新归档会**整包解压**取头——大归档场景请用 [loadManifest]
  /// （流式只读头部）。保留给旧版目录与索引重建等同步路径。
  CheckpointManifest manifestOf(String sessionId, int turn) {
    final File archive = archiveFile(sessionId, turn);
    if (archive.existsSync()) {
      return readCheckpointArchive(archive).$1;
    }
    final Directory? legacy = legacyDir(sessionId, turn);
    if (legacy != null) {
      final File gz = File(
        '${legacy.path}${Platform.pathSeparator}manifest.json.gz',
      );
      final File plain = File(
        '${legacy.path}${Platform.pathSeparator}manifest.json',
      );
      if (gz.existsSync() || plain.existsSync()) {
        final List<int> bytes = gz.existsSync()
            ? gzip.decode(gz.readAsBytesSync())
            : plain.readAsBytesSync();
        return CheckpointManifest.fromJson(
          jsonDecode(utf8.decode(bytes)) as Map<String, Object?>,
        );
      }
    }
    throw CheckpointException('missing-manifest', '检查点 $turn 缺少清单');
  }

  /// 异步读清单：新归档走流式头部读取（不整包解压），旧版目录回退 [manifestOf]。
  @override
  Future<CheckpointManifest> loadManifest(String sessionId, int turn) async {
    final File archive = archiveFile(sessionId, turn);
    if (archive.existsSync()) {
      return readCheckpointManifest(archive);
    }
    return manifestOf(sessionId, turn);
  }

  /// 恢复到 [turn] 轮（rsync 语义：目标态覆盖/补回，多余的删掉）。
  ///
  /// 符号链接越界校验在改动任何文件之前完成（fail-closed）。
  @override
  Future<CheckpointRestore> restore(String sessionId, int turn) =>
      restoreArchiveCheckpoint(this, sessionId, turn);

  /// 读 [path] 在 [turn] 轮的内容（base 铺底 + 差量覆盖）；见 [readArchiveFile]。
  @override
  Future<List<int>?> readFile(String sessionId, int turn, String path) =>
      readArchiveFile(this, sessionId, turn, path);

  /// 批量读：base / 差量各只解压一遍（见 `readArchiveFiles`）。
  @override
  Future<Map<String, List<int>>> readFiles(
    String sessionId,
    int turn,
    Iterable<String> paths,
  ) async {
    final Set<String> readable = <String>{
      for (final String path in paths)
        if (checkpointReadablePath(path, projectRel, policy)) path,
    };
    if (readable.isEmpty || !turnsOf(sessionId).contains(turn)) {
      return <String, List<int>>{};
    }
    try {
      return await readArchiveFiles(this, sessionId, turn, readable);
    } on CheckpointException {
      return <String, List<int>>{};
    }
  }

  /// [fromTurn] → [toTurn] 的文件级变化；见 [archiveChangesBetween]。
  @override
  Future<List<CheckpointFileChange>> changesBetween(
    String sessionId,
    int fromTurn,
    int toTurn,
  ) =>
      archiveChangesBetween(this, sessionId, fromTurn, toTurn);

  /// 现有检查点的摘要（turn 升序 + 有效文件数；索引缺失时按目录重建）。
  @override
  List<CheckpointInfo> list(String sessionId) {
    final List<CheckpointInfo>? cached = readCheckpointIndex(
      indexFile(sessionId),
    );
    if (cached != null) return cached;
    return _rebuildIndex(sessionId);
  }

  /// 现有检查点的轮次（升序）。
  @override
  List<int> turnsOf(String sessionId) => <int>[
        for (final CheckpointInfo info in list(sessionId)) info.turn,
      ];

  /// 保留 turn 0（base）+ 最近 `keep - 1` 个差量；[keep] 非正不裁剪。
  @override
  void prune(String sessionId) {
    if (keep <= 0) return;
    final List<CheckpointInfo> infos = list(sessionId);
    final List<CheckpointInfo> deltas =
        infos.where((CheckpointInfo i) => i.turn > 0).toList();
    final int excess = deltas.length - (keep - 1);
    if (excess <= 0) return;
    for (int index = 0; index < excess; index++) {
      _deleteTurn(sessionId, deltas[index].turn);
    }
    writeCheckpointIndex(indexFile(sessionId), <CheckpointInfo>[
      ...infos.where((CheckpointInfo i) => i.turn == 0),
      ...deltas.sublist(excess),
    ]);
  }

  void _upsertIndex(String sessionId, CheckpointInfo info) {
    final List<CheckpointInfo> infos = <CheckpointInfo>[
      ...list(sessionId).where((CheckpointInfo i) => i.turn != info.turn),
      info,
    ]..sort((CheckpointInfo a, CheckpointInfo b) => a.turn.compareTo(b.turn));
    writeCheckpointIndex(indexFile(sessionId), infos);
  }

  /// 索引缺失时重建：旧版可读目录 + 现有哈希归档头部。
  List<CheckpointInfo> _rebuildIndex(String sessionId) {
    final Directory dir = sessionDir(sessionId);
    if (!dir.existsSync()) return const <CheckpointInfo>[];
    final List<CheckpointInfo> infos = <CheckpointInfo>[];
    for (final FileSystemEntity entity in dir.listSync()) {
      final String name = entity.path.split(Platform.pathSeparator).last;
      // 索引本身、哈希旁挂文件、原子写的临时文件都不是归档。
      if (name == 'index' ||
          name.endsWith(kCheckpointHashesSuffix) ||
          name.endsWith(kCheckpointArchiveTempSuffix)) {
        continue;
      }
      if (entity is Directory) {
        final int? turn = int.tryParse(name);
        if (turn == null) continue;
        final CheckpointManifest manifest = manifestOf(sessionId, turn);
        infos.add(
          CheckpointInfo(turn: turn, files: _countFor(sessionId, manifest)),
        );
      } else if (entity is File) {
        // 无扩展名的哈希归档：读头部拿轮次。
        final (CheckpointManifest manifest, _) = readCheckpointArchive(entity);
        infos.add(
          CheckpointInfo(
            turn: manifest.turn,
            files: _countFor(sessionId, manifest),
          ),
        );
      }
    }
    infos.sort(
      (CheckpointInfo a, CheckpointInfo b) => a.turn.compareTo(b.turn),
    );
    writeCheckpointIndex(indexFile(sessionId), infos);
    return infos;
  }

  int _countFor(String sessionId, CheckpointManifest manifest) {
    if (!manifest.isDelta) return manifest.files.length;
    final Set<String> basePaths = <String>{
      for (final CheckpointFileEntry entry in manifestOf(sessionId, 0).files)
        entry.path,
    };
    final Set<String> deleted = manifest.deleted.toSet();
    return basePaths.where((String p) => !deleted.contains(p)).length +
        manifest.changed.where((String p) => !basePaths.contains(p)).length;
  }

  void _deleteTurn(String sessionId, int turn) {
    final File archive = archiveFile(sessionId, turn);
    if (archive.existsSync()) archive.deleteSync();
    deleteCheckpointHashes(archive); // 旁挂哈希随归档一起清
    legacyDir(sessionId, turn)?.deleteSync(recursive: true);
  }

  /// `projectDir` 相对 [root] 的路径（排除按相对路径比较）。
  String get projectRel {
    final String sep = Platform.pathSeparator;
    final String absRoot = root.endsWith(sep) ? root : '$root$sep';
    if (projectDir.startsWith(absRoot)) {
      return projectDir.substring(absRoot.length);
    }
    return projectDir;
  }
}

/// 差量 pass 1 的分类结果。
class _DeltaScan {
  const _DeltaScan({required this.changed, required this.current});

  /// 相对基线新增或修改的路径。
  final List<String> changed;

  /// 当前工作区的全部路径（用于算 deleted）。
  final Set<String> current;
}

/// 单文件 SHA-256（内存 ≈ 该文件自身；调用方逐文件调用，不累积）。
Future<String> _sha256File(File file) async =>
    sha256.convert(await file.readAsBytes()).toString();
