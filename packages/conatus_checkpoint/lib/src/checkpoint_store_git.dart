/// 影子仓库式快照存储：把工作区提交进一个独立的 git dir。
///
/// 布局：`<projectDir>/checkpoints/shadow.git`（仓库）+ 每会话一个索引
/// `shadow-index/<sessionId>`（gzip JSON，轮次 → 提交 sha，见
/// `shadow_index.dart`）。git dir 本身在排除区里，不会自噬。
///
/// 相对自研归档（`ArchiveCheckpointStore`）的取舍：
///
/// - **快**：内容寻址 + zlib + 增量全由 git 提供。同一文件改 N 次只存 N
///   份 blob（归档实现每个版本各存一份完整内容），且对象跨会话复用——
///   第二次打开会话不再重付全量代价（894MB 工作区首次约 20s，之后近乎为 0）。
/// - **依赖 git 二进制**：无 git 时不可用，由装配层降级回归档实现。
/// - **不要求工作区是仓库**：影子 git dir 与用户仓库完全解耦，实测用户
///   仓库的 `status` / `log` 不受影子提交影响。这正是选影子而非用户仓库
///   的理由——agent 的 wip 提交不该混进用户历史。
///
/// 与归档实现共享的语义（见 `CheckpointStore`）：rsync 式恢复、符号链接
/// 不进快照、恢复前 fail-closed 越界校验、`projectDir` 与策略排除。
///
// REASON: 单一协议实现（暂存 / 提交 / 索引 / 裁剪 / 恢复）共享私有状态与
// git 调用时序；按行数拆分需把暂存校验与索引命名的内部契约暴露出去，
// 反而扩大回归面（归档实现同此取舍）。
library;

import 'dart:convert';
import 'dart:io';

import 'package:conatus_foundation/conatus_foundation.dart';

import 'checkpoint_changes.dart';
import 'checkpoint_io.dart';
import 'checkpoint_paths.dart';
import 'checkpoint_policy.dart';
import 'checkpoint_scan.dart';
import 'checkpoint_store.dart';
import 'checkpoint_types.dart';
import 'global_git_ignore.dart';
import 'shadow_git_runner.dart';
import 'shadow_index.dart';

/// 影子仓库式快照存储。
class GitShadowStore implements CheckpointStore {
  GitShadowStore({
    required String root,
    required this.projectDir,
    this.keep = 5,
    this.policy = const CheckpointPolicy(),
    GitRunner? git,
  })  : root = Directory(root).absolute.path,
        _git = git ?? const ProcessGitRunner();

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

  final GitRunner _git;

  /// 全局 gitignore 解析出的排除集（每轮快照重算：文件在变）。
  ///
  /// 采集与删除判定共用它——两者不同源就是 swiftus 删 9119 个文件的根因。
  Set<String> _extraExcluded = const <String>{};

  /// 解析全局 gitignore 并记入 [_extraExcluded]；解析不出来就留空集
  /// （保守降级：多收只是快照大一点，不会丢数据）。
  Future<void> _resolveGlobalIgnores(List<String> candidates) async {
    _extraExcluded = await resolveGlobalGitIgnore(
      git: _git,
      gitDir: gitDir,
      workTree: root,
      candidates: candidates,
    );
  }

  /// 影子仓库目录（[projectDir] 下的 `checkpoints/shadow.git`）。
  ///
  /// 保持在 `projectDir` 内而非工作区根下：`projectDir` 整树已被
  /// `kCheckpointDefaultIgnores` 之外的 `projectDir` 规则排除（见
  /// `_writeExcludes`），故影子仓库自身不会被 `add --all` 卷进快照——
  /// 这点由 `排除项` 用例守住。路径必须**规范化**（无 `..`）：git 要求
  /// `--git-dir` 与 `--work-tree` 不互相包含，带 `..` 会直接报 fatal。
  String get gitDir =>
      Directory(sessionRoot()).absolute.path +
      Platform.pathSeparator +
      _shadowDirName;

  /// 影子仓库目录名。
  static const String _shadowDirName = 'shadow.git';

  /// 检查点根目录（会话索引所在；与影子仓库同级）。
  String sessionRoot() => '$projectDir${Platform.pathSeparator}checkpoints';

  /// 某会话的索引文件。
  File indexFile(String sessionId) => File(
        '${sessionRoot()}${Platform.pathSeparator}shadow-index'
        '${Platform.pathSeparator}$sessionId',
      );

  /// 环境里是否有可用 git；装配层据此决定用本实现还是归档实现。
  Future<bool> gitAvailable() => _git.available();

  // ---- 存储契约 -------------------------------------------------------

  @override
  Future<void> clearSession(String sessionId) async {
    final List<ShadowCheckpointRef> refs = _refs(sessionId);
    for (final ShadowCheckpointRef ref in refs) {
      await _gitObj(<String>['tag', '-d', _tag(sessionId, ref.turn)]);
    }
    // 索引连同它独占的提交一起清；对象留着（可能被别的会话/轮次引用，
    // 清了要重写可达性，收益不抵风险）。
    final File index = indexFile(sessionId);
    if (index.existsSync()) await index.delete();
  }

  @override
  Future<void> snapshot(
    String sessionId,
    int turn, {
    String? lastEventId,
  }) async {
    await _ensureRepo();
    await _stageWorktree();
    final GitResult commit = await _gitObj(<String>[
      'commit',
      '--allow-empty',
      '--quiet',
      '-m',
      'turn $turn${lastEventId == null ? '' : ' $lastEventId'}',
    ]);
    _expect(commit, '提交影子快照');
    final String sha = _headSha();
    final String tag = _tag(sessionId, turn);
    await _gitObj(<String>['tag', '--force', tag, sha]);
    await _gitObj(<String>[
      'update-ref',
      'refs/checkpoints/$sessionId/$turn',
      sha,
    ]);
    _upsert(
      sessionId,
      ShadowCheckpointRef(
        turn: turn,
        commit: sha,
        files: _fileCount(sha),
        lastEventId: lastEventId,
      ),
    );
    await _restrictArtifacts(sessionId);
    prune(sessionId);
  }

  /// 收紧影子仓库落盘权限（E-12）：`checkpoints` 目录 0700 挡住其他用户遍历
  /// （`shadow.git` 与 `shadow-index` 都在其下），会话索引 600 兜底。
  Future<void> _restrictArtifacts(String sessionId) async {
    final File index = indexFile(sessionId);
    if (index.existsSync()) await restrictFilePermissions(index.path);
    await restrictDirectoryPermissions(sessionRoot());
  }

  @override
  List<CheckpointInfo> list(String sessionId) => <CheckpointInfo>[
        for (final ShadowCheckpointRef ref in _refs(sessionId))
          CheckpointInfo(turn: ref.turn, files: ref.files),
      ];

  @override
  List<int> turnsOf(String sessionId) => <int>[
        for (final ShadowCheckpointRef r in _refs(sessionId)) r.turn,
      ];

  @override
  Future<CheckpointManifest> loadManifest(String sessionId, int turn) async {
    final List<ShadowCheckpointRef> refs = _refs(sessionId);
    for (final ShadowCheckpointRef ref in refs) {
      if (ref.turn == turn) return ref.toManifest();
    }
    throw CheckpointException(
      'missing-manifest',
      '检查点 $turn 缺少清单（会话 $sessionId）',
    );
  }

  @override
  Future<CheckpointRestore> restore(String sessionId, int turn) async {
    final String? sha = _commitOf(sessionId, turn);
    if (sha == null) {
      throw const CheckpointException('missing-checkpoint', '检查点不存在');
    }
    final List<String> paths = _lsTree(sha);
    // fail-closed：只读路径绝不能物化回工作区——`read-tree --reset -u` 会把
    // 旧快照里的只读目录原样写回（采集侧此前未排除）。
    _rejectReadOnlyTree(paths);
    // fail-closed：先校验全部路径（目标态 + 将被删除的当前文件），
    // 任何越界都在改动一个文件之前抛。
    ensurePathsRestorable(root, paths);
    // 全局 gitignore 的排除集只有 snapshot 会算。接管已有时间线（bind 不拍
    // 快照）后首次恢复直接走到这里，不重算就会把它命中的文件当成「目标态
    // 没有的多余文件」删掉——不可恢复。恢复是显式低频动作，多两遍 walk 值得。
    // 候选集用 [_candidatePaths]：被上一轮排除集剪过的路径问不到 git，重算
    // 反而会把它丢掉（自己抹掉自己）。
    await _resolveGlobalIgnores(await _candidatePaths());
    final Set<String> target = paths.toSet();
    final int removed = await _deleteExtras(target);
    // `read-tree --reset -u` 把工作区精确重置到该提交（含删除之后新增的
    // 文件）。`checkout <sha> -- .` 做不到删除，故不用。
    final GitResult reset = await _gitObj(<String>[
      'read-tree',
      '--reset',
      '-u',
      sha,
    ]);
    _expect(reset, '恢复工作区');
    return CheckpointRestore(restored: paths.length, deleted: removed);
  }

  @override
  void prune(String sessionId) {
    if (keep <= 0) return;
    final List<ShadowCheckpointRef> refs = _refs(sessionId);
    final List<ShadowCheckpointRef> deltas =
        refs.where((ShadowCheckpointRef r) => r.turn > 0).toList();
    final int excess = deltas.length - (keep - 1);
    if (excess <= 0) return;
    for (int i = 0; i < excess; i++) {
      _gitObjSync(<String>['tag', '-d', _tag(sessionId, deltas[i].turn)]);
      _gitObjSync(<String>[
        'update-ref',
        '-d',
        'refs/checkpoints/$sessionId/${deltas[i].turn}',
      ]);
    }
    writeShadowIndex(indexFile(sessionId), <ShadowCheckpointRef>[
      ...refs.where((ShadowCheckpointRef r) => r.turn == 0),
      ...deltas.sublist(excess),
    ]);
  }

  // ---- git 内部操作 ---------------------------------------------------

  /// 目标树含只读路径（`policy.readOnlyPrefixes`）时整体拒绝恢复。
  ///
  /// `read-tree --reset -u` 没有「逐条跳过」的形态：要么整棵树写回，要么
  /// 一个字都不动。因此只能 fail-closed，提示用户该快照不可恢复，而不是
  /// 静默把只读目录物化出来。
  void _rejectReadOnlyTree(List<String> paths) {
    for (final String path in paths) {
      if (!checkpointReadOnlyPath(path, policy.readOnlyPrefixes)) continue;
      throw CheckpointException(
        'read-only-path',
        '检查点含只读路径（$path），已拒绝恢复：只读目录不可写回',
      );
    }
  }

  /// 读 [path] 在 [turn] 轮的内容；不在该树 / 只读 / 越界返回 `null`。
  ///
  /// 走 `git show <commit>:<path>`（内容寻址，无需 diff 基线）。二进制内容
  /// 取 [GitResult.stdoutBytes]——按字符串读会把非法 UTF-8 换成 U+FFFD。
  @override
  Future<List<int>?> readFile(String sessionId, int turn, String path) async {
    if (!checkpointReadablePath(path, projectRel, policy)) return null;
    final String? sha = _commitOf(sessionId, turn);
    if (sha == null) return null;
    final GitResult result = await _gitObj(<String>['show', '$sha:$path']);
    if (!result.ok) return null;
    return result.stdoutBytes ?? const Utf8Encoder().convert(result.stdout);
  }

  /// 批量读：逐路径 `git show`（影子仓库没有可比归档更快的批式接口，
  /// 但内容寻址让单次读取足够便宜；缺失路径直接跳过）。
  @override
  Future<Map<String, List<int>>> readFiles(
    String sessionId,
    int turn,
    Iterable<String> paths,
  ) async {
    final Map<String, List<int>> found = <String, List<int>>{};
    for (final String path in paths) {
      final List<int>? bytes = await readFile(sessionId, turn, path);
      if (bytes != null) found[path] = bytes;
    }
    return found;
  }

  /// [fromTurn] → [toTurn] 的文件级变化（`git diff --name-status -z -M`）。
  @override
  Future<List<CheckpointFileChange>> changesBetween(
    String sessionId,
    int fromTurn,
    int toTurn,
  ) async {
    final String? from = _commitOf(sessionId, fromTurn);
    final String? to = _commitOf(sessionId, toTurn);
    if (from == null || to == null) {
      throw CheckpointException(
        'missing-checkpoint',
        '检查点不存在：会话 $sessionId 的第 $fromTurn / $toTurn 轮',
      );
    }
    if (from == to) return const <CheckpointFileChange>[];
    final GitResult diff = await _gitObj(<String>[
      'diff',
      '--name-status',
      '-z',
      '-M',
      from,
      to,
    ]);
    _expect(diff, '比较检查点');
    final List<CheckpointFileChange> changes = <CheckpointFileChange>[
      for (final CheckpointFileChange change in parseCheckpointNameStatus(
        diff.stdout,
      ))
        if (checkpointReadablePath(change.path, projectRel, policy)) change,
    ]..sort(
        (CheckpointFileChange a, CheckpointFileChange b) =>
            a.path.compareTo(b.path),
      );
    return changes;
  }

  /// 单次 `git add` 传多少路径（argv 长度上限的保守取值）。
  static const int _addBatchSize = 400;

  /// 把工作区当前状态暂存进影子仓库的索引。
  ///
  /// **不用 `git add --all`**：那会让 git 顺从工作区的 `.gitignore`
  /// （Swift 项目的 `.build/`、前端项目的 `dist/` 都在里面），而归档实现
  /// 只认 `kCheckpointDefaultIgnores` + 策略。两者一旦不一致，
  /// 恢复时的 rsync 删除就会按残缺清单把文件删掉——实测在 9661 文件的
  /// swiftus 工作区上，影子快照只收了 293 个，恢复删掉了其余 9119 个。
  ///
  /// 故排除判定完全由我们自己做（[checkpointWalk]，与归档实现同一份
  /// 代码），再把结果**显式路径**喂给 `git add -f`：`-f` 覆盖 ignore
  /// 规则，既然只传我们想要的，结果就等于自定义排除面。分批是因为 argv
  /// 长度有限。
  Future<void> _stageWorktree() async {
    // 先用**不受全局 ignore 影响**的候选集问 git（[_candidatePaths]），再带着
    // 结果重走一次——两遍只为把全局排除并进同一个判定源，避免采集与删除判定
    // 分家。候选集不能按旧 `_extraExcluded` 剪枝：被上轮排除的文件问不到 git，
    // 下一轮解析结果就少一项，全局忽略的文件会在第二轮快照里被重新收进来。
    final List<String> candidates = await _candidatePaths();
    await _resolveGlobalIgnores(candidates);
    final List<String> wanted = await _walkPaths();
    for (final List<String> batch in _batched(wanted)) {
      _expect(await _gitObj(<String>['add', '-f', '--', ...batch]), '暂存工作区');
    }
    // 删除：已跟踪但磁盘上已不存在的路径要显式从索引摘掉。`git add` 只处理
    // 「传进去的路径」，看不到这些——不摘的话本轮会把它们当成还在。
    for (final List<String> batch in _batched(_trackedButGone())) {
      _expect(
        await _gitObj(<String>[
          'rm',
          '--cached',
          '--quiet',
          '--ignore-unmatch',
          '--',
          ...batch,
        ]),
        '记录已删除的文件',
      );
    }
    _verifyStaged(wanted);
  }

  /// 断言索引确实收到了我们想暂存的每一个路径，否则**报错**。
  ///
  /// 绝不静默放过：`git add` 对「显式指定的路径落在嵌套版本库里」会**跳过
  /// 且退出码 0、无告警**。一旦漏暂存，本轮快照就是残缺的，而恢复的 rsync
  /// 语义会按残缺清单把那些文件删掉——这是本实现踩过的最严重的一个坑
  /// （9661 文件的 swiftus 上快照只收 293 个，恢复删掉 9119 个；修掉
  /// `.gitignore` 之后又在带 `git worktree` 的项目上复现一次）。
  ///
  /// 嵌套版本库已由 [checkpointExcluded] 整树排除，故正常路径下这里恒等。
  /// 它是**兜底断言**：将来冒出新的「git 静默不收」的情形，至少会变成一条
  /// 可见的检查点错误（编排层转成屏上提示），而不是悄悄损坏回滚能力。
  void _verifyStaged(List<String> wanted) {
    if (wanted.isEmpty) return;
    final GitResult indexed = _gitObjSync(<String>[
      'ls-files',
      '-z',
      '--cached',
    ]);
    _expect(indexed, '核对暂存结果');
    final Set<String> have = <String>{
      for (final String p in indexed.stdout.split('\u0000'))
        if (p.isNotEmpty) p,
    };
    final List<String> missing =
        wanted.where((String p) => !have.contains(p)).toList();
    if (missing.isEmpty) return;
    final String sample = missing.take(3).join(', ');
    throw CheckpointException(
      'stage-incomplete',
      '暂存不完整：${missing.length} 个文件未被 git 收录（$sample'
          '${missing.length > 3 ? ' 等' : ''}）。已中止本轮快照，'
          '以免恢复时按残缺清单误删文件。',
    );
  }

  /// 自己 walk 出来的应入快照路径（与归档实现同一套排除判定）。
  Future<List<String>> _walkPaths() async {
    return _walkWithExtra(_extraExcluded);
  }

  /// 解析全局 gitignore 用的候选集：**不按**当前 `_extraExcluded` 剪枝。
  ///
  /// `_extraExcluded` 是上一轮解析的产物，而 [_resolveGlobalIgnores] 会**整体
  /// 替换**它。若拿被它剪过的路径去问 git，命中项根本不在候选集里，重算结果
  /// 就会变小——全局忽略的文件在第二轮快照 / 恢复里被重新收进来或被删掉。
  Future<List<String>> _candidatePaths() async {
    return _walkWithExtra(const <String>{});
  }

  Future<List<String>> _walkWithExtra(Set<String> extra) async {
    final List<String> paths = <String>[];
    await for (final FileSystemEntity entity in checkpointWalk(
      root,
      projectRel,
      policy,
      extra,
    )) {
      paths.add(checkpointRelativeTo(entity, root));
    }
    return paths;
  }

  /// 已被影子仓库跟踪、但当前工作区已不存在的路径。
  List<String> _trackedButGone() {
    final GitResult tracked = _gitObjSync(<String>[
      'ls-files',
      '-z',
      '--cached',
    ]);
    if (!tracked.ok) return const <String>[];
    return <String>[
      for (final String rel in tracked.stdout.split('\u0000'))
        if (rel.isNotEmpty &&
            !File('$root${Platform.pathSeparator}$rel').existsSync())
          rel,
    ];
  }

  /// 把路径切成不超过 [_addBatchSize] 的批。
  static Iterable<List<String>> _batched(List<String> paths) sync* {
    for (int i = 0; i < paths.length; i += _addBatchSize) {
      yield paths.sublist(
        i,
        i + _addBatchSize > paths.length ? paths.length : i + _addBatchSize,
      );
    }
  }

  /// 确保影子仓库已初始化，并把排除项写进 `.git/info/exclude`。
  Future<void> _ensureRepo() async {
    if (!Directory(gitDir).existsSync()) {
      // git init 要求 --git-dir 的**父目录**已存在（否则报
      // `Invalid path ... No such file or directory`）。
      Directory(gitDir).parent.createSync(recursive: true);
      final GitResult init = await _gitObj(<String>['init', '--quiet']);
      _expect(init, '初始化影子仓库');
    }
    await _writeExcludes();
  }

  /// 写排除规则：`.git`、内置默认项、`projectDir` 整树、策略前缀。
  ///
  /// 写进 `.git/info/exclude` 而非工作区的 `.gitignore`——后者会被当作
  /// 快照内容提交进去，且会污染用户项目。
  Future<void> _writeExcludes() async {
    final File file = File(
      '$gitDir${Platform.pathSeparator}info'
      '${Platform.pathSeparator}exclude',
    );
    final String body = <String>[
      '# conatus 检查点影子仓库的排除项（勿手改：每次快照前重写）',
      for (final String prefix in kCheckpointDefaultIgnores) '$prefix/',
      if (projectRel.isNotEmpty) '${projectRel.replaceAll('\\', '/')}/',
      for (final String prefix in _policyPrefixes)
        '${prefix.replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), '')}/',
      '',
    ].join('\n');
    file.parent.createSync(recursive: true);
    await file.writeAsString(body, flush: true);
  }

  /// 策略声明的全部排除前缀（ignore / excluded / readOnly）。
  List<String> get _policyPrefixes => <String>[
        ...policy.ignore,
        ...policy.excludedPrefixes,
        ...policy.readOnlyPrefixes,
      ];

  /// 当前 HEAD 的提交 sha（短 sha 够用：只在本仓库内比对）。
  String _headSha() {
    final GitResult result = _gitObjSync(<String>['rev-parse', 'HEAD']);
    _expect(result, '读取 HEAD');
    return result.stdout.trim();
  }

  /// 该提交树里的文件数（`git ls-tree -r` 计数，供列表展示）。
  int _fileCount(String sha) => _lsTree(sha).length;

  /// 该提交树里的全部文件路径（相对工作区根）。
  List<String> _lsTree(String sha) {
    final GitResult result = _gitObjSync(<String>[
      'ls-tree',
      '-r',
      '--name-only',
      '-z',
      sha,
    ]);
    _expect(result, '读取提交树');
    return <String>[
      for (final String path in result.stdout.split('\u0000'))
        if (path.isNotEmpty) path,
    ];
  }

  /// 删除当前工作区中「不在目标态、且未被排除」的文件；返回删除数。
  ///
  /// 排除项必须跳过：影子 git dir 就在 `projectDir` 下，删掉它等于自毁。
  /// 嵌套版本库整棵跳过——它本就不在快照里（[checkpointWalk] 剪掉了），
  /// 这里若不跳过，恢复就会把它当成「目标态没有的多余文件」整棵删掉。
  Future<int> _deleteExtras(Set<String> target) async {
    final List<String> extras = <String>[];
    await for (final FileSystemEntity entity in checkpointWalk(
      root,
      projectRel,
      policy,
      _extraExcluded,
    )) {
      final String rel = checkpointRelativeTo(entity, root);
      if (!target.contains(rel)) extras.add(rel);
    }
    for (final String rel in extras) {
      // 防御性：walk 已排除链接，父链仍可能是。
      ensureRestorable(root, rel);
      File('$root${Platform.pathSeparator}$rel').deleteSync();
    }
    return extras.length;
  }

  // ---- 索引 -----------------------------------------------------------

  List<ShadowCheckpointRef> _refs(String sessionId) =>
      readShadowIndex(indexFile(sessionId));

  String? _commitOf(String sessionId, int turn) {
    for (final ShadowCheckpointRef ref in _refs(sessionId)) {
      if (ref.turn == turn) return ref.commit;
    }
    return null;
  }

  void _upsert(String sessionId, ShadowCheckpointRef ref) {
    writeShadowIndex(indexFile(sessionId), <ShadowCheckpointRef>[
      for (final ShadowCheckpointRef old in _refs(sessionId))
        if (old.turn != ref.turn) old,
      ref,
    ]);
  }

  /// 会话 + 轮次的 tag 名（不可读名不适用于 git：tag 本就可见，
  /// 但用 `refs/checkpoints/` 前缀把检查点与用户分支隔开）。
  String _tag(String sessionId, int turn) => 'checkpoints/$sessionId/$turn';

  /// `projectDir` 相对 [root] 的路径（排除按相对路径比较）。
  String get projectRel {
    final String sep = Platform.pathSeparator;
    final String absRoot = root.endsWith(sep) ? root : '$root$sep';
    if (projectDir.startsWith(absRoot)) {
      return projectDir.substring(absRoot.length);
    }
    return projectDir;
  }

  // ---- 执行 -----------------------------------------------------------

  Future<GitResult> _gitObj(List<String> args) =>
      _git.run(args, gitDir: gitDir, workTree: root);

  /// 同步版（`list`/`prune` 这类同步接口用；会阻塞事件循环，故只用于
  /// 低频路径）。
  GitResult _gitObjSync(List<String> args) =>
      _git.runSync(args, gitDir: gitDir, workTree: root);

  /// git 失败转成 [CheckpointException]（编排层转成提示，不打断轮次）。
  void _expect(GitResult result, String what) {
    if (result.ok) return;
    final String detail = result.stderr.trim().isEmpty
        ? '退出码 ${result.exitCode}'
        : result.stderr.trim();
    throw CheckpointException('git-failed', '$what 失败：$detail');
  }
}
