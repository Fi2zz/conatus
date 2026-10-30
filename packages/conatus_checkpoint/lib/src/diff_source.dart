/// `/diff` 的数据源：工作区 git 差异与检查点轮次差异。
///
/// 只读：不写工作区、不动检查点；无 git 或检查点缺失时返回空列表（工作区
/// 范围回落到轮次范围）。二进制与超大文件由 `diffLines` 降级为文件级结论。
library;

import 'dart:convert';

import 'package:conatus_diff/conatus_diff.dart';

import 'checkpoint_changes.dart';
import 'checkpoint_manager.dart';
import 'checkpoint_types.dart';
import 'working_diff.dart';

/// 「还没有可比较的轮次」的说明（turn 0 只表示基线，没有上一轮可比）。
const String kDiffNoTurnNotice = '还没有可比较的轮次（第 1 轮收口后才有 diff）。';

/// 按范围加载文件级差异。
class DiffSource {
  DiffSource({
    required this.workdir,
    required this.checkpoint,
    required this.sessionId,
    this.turn,
  });

  /// 工作区根（绝对路径）。
  final String workdir;

  /// 检查点管理器（只走公开透传）。
  final CheckpointManager checkpoint;

  /// 会话 id。
  final String sessionId;

  /// 目标轮次；`null` 表示先 `flush()` 再取管理器当时的轮次（`/diff turn`
  /// 的缺省语义：刚收口的一轮才算「本轮」）。
  final int? turn;

  String? _notice;

  /// 最近一次 `load` 的降级说明（git 命令失败等）；正常为 `null`。
  String? get notice => _notice;

  /// 加载 [scope] 范围内的差异（按路径排序）。
  Future<List<FileDiff>> load(DiffScope scope) async {
    _notice = null;
    if (scope == DiffScope.turn) return _turnDiff();
    final WorkingDiff working = WorkingDiff(
      workdir,
      acceptsPath: checkpoint.showsDiffPath,
    );
    final List<FileDiff>? diffs = await working.load();
    _notice = working.notice;
    return diffs ?? _turnDiff(fromWorking: true);
  }

  /// 检查点轮次差异：目标轮 vs 上一轮。
  ///
  /// 先 `flush()`：`recordTurn` 同步推进轮次、归档稍后落盘，刚结束一轮就
  /// 打开的 `/diff` 不等它就会撞上 `missing-checkpoint`。轮次为 0 时没有
  /// 「上一轮」——`/diff turn` 返回空列表并给出说明，而不是把整个基线当成
  /// 新增文件；`working` 在无 git 时回落，此时基线就是唯一可看的东西。
  Future<List<FileDiff>> _turnDiff({bool fromWorking = false}) async {
    await checkpoint.flush();
    final int target = turn ?? checkpoint.turn;
    if (target <= 0) {
      if (!fromWorking) {
        _notice = kDiffNoTurnNotice;
        return const <FileDiff>[];
      }
      try {
        return _sorted(await _fromEmpty());
      } on CheckpointException {
        return const <FileDiff>[];
      }
    }
    try {
      return _sorted(await _between(target - 1, target));
    } on CheckpointException {
      return const <FileDiff>[];
    }
  }

  /// 基线（turn 0）相对空内容的差异：工作区回落时展示初始文件清单。
  Future<List<FileDiff>> _fromEmpty() async {
    final CheckpointManifest manifest = await checkpoint.loadManifest(
      sessionId,
      0,
    );
    final List<String> paths = <String>[
      for (final CheckpointFileEntry entry in manifest.files)
        if (checkpoint.showsDiffPath(entry.path)) entry.path,
    ];
    final Map<String, List<int>> contents = await checkpoint.readFiles(
      sessionId,
      0,
      paths,
    );
    return <FileDiff>[
      for (final String path in paths)
        for (final FileDiff diff in diffLines(
          path,
          null,
          _text(contents[path]),
        ))
          diff,
    ];
  }

  /// 两侧内容各批量读一次（归档实现只解压 base / 差量各一遍）。
  Future<List<FileDiff>> _between(int fromTurn, int toTurn) async {
    final List<CheckpointFileChange> changes =
        (await checkpoint.changesBetween(sessionId, fromTurn, toTurn))
            .where(
              (CheckpointFileChange change) =>
                  checkpoint.showsDiffPath(change.path),
            )
            .toList(growable: false);
    final Set<String> paths = <String>{
      for (final CheckpointFileChange change in changes) change.path,
    };
    final Map<String, List<int>> before = await checkpoint.readFiles(
      sessionId,
      fromTurn,
      paths,
    );
    final Map<String, List<int>> after = await checkpoint.readFiles(
      sessionId,
      toTurn,
      paths,
    );
    return <FileDiff>[
      for (final CheckpointFileChange change in changes)
        ..._changeDiff(
          change,
          _text(before[change.path]),
          _text(after[change.path]),
        ),
    ];
  }

  /// 两端内容都读不出（旧格式检查点）时仍保留一条文件级变化，而不是静默丢掉。
  /// 重命名保留状态词（存储只给新路径）。
  List<FileDiff> _changeDiff(
    CheckpointFileChange change,
    String? before,
    String? after,
  ) {
    if (before == null && after == null) {
      return <FileDiff>[
        FileDiff(path: change.path, status: change.status, hunks: const []),
      ];
    }
    final List<FileDiff> diffs = diffLines(change.path, before, after);
    if (change.status != 'renamed') return diffs;
    return <FileDiff>[
      for (final FileDiff diff in diffs) diff.copyWith(status: 'renamed'),
    ];
  }

  String? _text(List<int>? bytes) =>
      bytes == null ? null : utf8.decode(bytes, allowMalformed: true);

  List<FileDiff> _sorted(List<FileDiff> diffs) =>
      diffs..sort((FileDiff a, FileDiff b) => a.path.compareTo(b.path));
}
