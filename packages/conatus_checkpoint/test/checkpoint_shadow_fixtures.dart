/// 影子 git 测试夹具：临时「用户项目 + 影子仓库」与直接问仓库的辅助命令。
///
/// 工作区**本身就是 git 仓库**——这是要验的重点：影子提交不得污染它。
library;

import 'dart:convert';
import 'dart:io';

import 'package:conatus_checkpoint/conatus_checkpoint.dart';
import 'package:test/test.dart';

import 'checkpoint_fixtures.dart';

/// 在 nava 只读策略上叠加额外 ignore / excluded 前缀。
CheckpointPolicy shadowPolicy({
  List<String> ignore = const <String>[],
  List<String> excluded = const <String>[],
}) =>
    CheckpointPolicy(
      ignore: ignore,
      excludedPrefixes: excluded,
      readOnlyPrefixes: kProductPolicy.readOnlyPrefixes,
    );

/// 一个已初始化影子仓库的临时工作区。
class ShadowFixture {
  ShadowFixture({
    int keep = 5,
    CheckpointPolicy policy = kProductPolicy,
  }) {
    root = _dir.path;
    projectDir = '$root$pathSep.conatus';
    Directory(projectDir).createSync();
    Process.runSync('git', <String>['init', '--quiet', root]);
    store = GitShadowStore(
      root: root,
      projectDir: projectDir,
      keep: keep,
      policy: policy,
    );
  }

  final Directory _dir = Directory.systemTemp.createTempSync('conatus-shadow');
  late final String root;
  late final String projectDir;
  late final GitShadowStore store;

  void write(String rel, String content) => writeWorkspace(root, rel, content);
  String read(String rel) => readWorkspace(root, rel);
  bool has(String rel) => workspaceHas(root, rel);
  String path(String rel) => '$root$pathSep$rel';

  /// 在影子仓库里跑一条 git 命令（造旧格式提交 / 读对象用），返回 stdout。
  String shadowGit(List<String> args) {
    final ProcessResult result = Process.runSync('git', <String>[
      '--git-dir=${store.gitDir}',
      '--work-tree=$root',
      '-c', 'user.email=conatus@localhost',
      '-c', 'user.name=conatus',
      // 身份与生产执行器（`ProcessGitRunner`）一致，并同样固定签名 / hook：
      // 影子提交不得依赖宿主 git 配置。
      '-c', 'commit.gpgsign=false',
      '-c', 'core.hooksPath=/dev/null',
      ...args,
    ]);
    if (result.exitCode != 0) {
      throw StateError('git ${args.join(' ')} 失败：${result.stderr}');
    }
    return result.stdout is String ? result.stdout! as String : '';
  }

  /// 某轮提交树里的文件路径。
  List<String> lsTree(String sha) {
    final String out = shadowGit(<String>[
      'ls-tree',
      '-r',
      '--name-only',
      '-z',
      sha,
    ]);
    return <String>[
      for (final String p in out.split('\u0000'))
        if (p.isNotEmpty) p,
    ];
  }

  /// 某轮的提交 sha。
  String commitOf(String sessionId, int turn) => shadowGit(<String>[
        'rev-list',
        '--max-count=1',
        'checkpoints/$sessionId/$turn',
      ]).trim();

  /// 该会话 `refs/checkpoints/<session>` 下的全部引用（逐行，无匹配为空）。
  List<String> refsOf(String sessionId) => <String>[
        for (final String line in shadowGit(<String>[
          'for-each-ref',
          'refs/checkpoints/$sessionId',
        ]).split('\n'))
          if (line.isNotEmpty) line,
      ];

  /// 影子仓库对象库的总字节（loose + pack）。
  int objectStoreBytes() {
    final String out = shadowGit(<String>['count-objects', '-v']);
    // 输出形如 `size: 1234\ncount: 5\n...`；用 size（磁盘占用）判断是否重存。
    for (final String line in out.split('\n')) {
      if (line.startsWith('size:')) {
        return int.tryParse(line.substring(5).trim()) ?? 0;
      }
    }
    return 0;
  }

  /// 把影子索引里某轮的提交改成 [sha]（模拟「旧版本写入的快照」）。
  void pointIndexAt(String sessionId, int turn, String sha) {
    final File index = store.indexFile(sessionId);
    final Map<String, Object?> json =
        jsonDecode(utf8.decode(gzip.decode(index.readAsBytesSync())))
            as Map<String, Object?>;
    final List<Map<String, Object?>> turns = <Map<String, Object?>>[
      for (final Object? item
          in (json['turns'] as List<Object?>?) ?? const <Object?>[])
        if (item is Map)
          <String, Object?>{
            ...item.cast<String, Object?>(),
            if (item['turn'] == turn) 'commit': sha,
          },
    ];
    index.writeAsBytesSync(
      gzip.encode(utf8.encode(jsonEncode(<String, Object?>{'turns': turns}))),
    );
  }

  void dispose() {
    if (_dir.existsSync()) _dir.deleteSync(recursive: true);
  }
}

/// 建夹具并登记卸载（只能在测试内调用）。
ShadowFixture createShadowFixture({
  int keep = 5,
  CheckpointPolicy policy = kProductPolicy,
}) {
  final ShadowFixture fixture = ShadowFixture(keep: keep, policy: policy);
  addTearDown(fixture.dispose);
  return fixture;
}
