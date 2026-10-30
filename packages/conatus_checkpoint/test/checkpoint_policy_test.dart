/// CheckpointPolicy：排除面与只读前缀（声明、大小写、嵌套、兄弟目录、
/// 遍历剪枝与恢复不写回）。
library;

import 'dart:io';

import 'package:conatus_checkpoint/conatus_checkpoint.dart';
import 'package:test/test.dart';

/// 宿主注入的产品策略（旧实现里硬编码的那两条）。
const CheckpointPolicy kReadOnlyProduct = CheckpointPolicy(
  readOnlyPrefixes: <String>['.opencode', '.config/opencode'],
);

String get _sep => Platform.pathSeparator;

void _write(String root, String rel, String content) {
  final File file = File('$root$_sep$rel');
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(content);
}

String _read(String root, String rel) =>
    File('$root$_sep$rel').readAsStringSync();

bool _exists(String root, String rel) => File('$root$_sep$rel').existsSync();

void main() {
  test('只读前缀只在 policy 声明时才排除；包内默认值不含产品目录', () {
    expect(
      checkpointExcluded('.opencode/config.json', '.conatus', kReadOnlyProduct),
      isTrue,
    );
    expect(
      checkpointExcluded(
        '.opencode/config.json',
        '.conatus',
        const CheckpointPolicy(),
      ),
      isFalse,
      reason: '包内只排除 build / .dart_tool / node_modules',
    );
    expect(kCheckpointDefaultIgnores, isNot(contains('.opencode')));
    expect(kCheckpointDefaultIgnores, isNot(contains('.config/opencode')));
  });

  test('只读前缀大小写不敏感', () {
    expect(checkpointReadOnlyPath('.OPENCODE/x', const <String>['.opencode']),
        isTrue);
    expect(checkpointExcluded('.OpenCode/x', '.conatus', kReadOnlyProduct),
        isTrue);
    expect(
      checkpointReadablePath('.OPENCODE/x', '.conatus', kReadOnlyProduct),
      isFalse,
    );
  });

  test('嵌套只读前缀按路径匹配（.config/opencode）', () {
    expect(
      checkpointExcluded(
        '.config/opencode/config.json',
        '.app',
        kReadOnlyProduct,
      ),
      isTrue,
    );
    expect(
      checkpointReadablePath(
          '.config/opencode/config.json', '.app', kReadOnlyProduct),
      isFalse,
    );
    expect(
      checkpointExcluded('.config/other/config.json', '.app', kReadOnlyProduct),
      isFalse,
    );
  });

  test('兄弟目录不误伤（前缀必须按段匹配）', () {
    expect(
      checkpointExcluded('opencodeX/x', '.conatus', kReadOnlyProduct),
      isFalse,
    );
    expect(
      checkpointExcluded('.opencodeX/x', '.conatus', kReadOnlyProduct),
      isFalse,
    );
    expect(
      checkpointExcluded('.config/opencodeX/x', '.conatus', kReadOnlyProduct),
      isFalse,
    );
  });

  test('excludedPrefixes / ignore / 默认排除各自生效', () {
    const CheckpointPolicy policy = CheckpointPolicy(
      excludedPrefixes: <String>['dist'],
      ignore: <String>['logs'],
    );
    expect(checkpointExcluded('dist/app.js', '.conatus', policy), isTrue);
    expect(checkpointExcluded('logs/a.log', '.conatus', policy), isTrue);
    expect(checkpointExcluded('build/x', '.conatus', policy), isTrue);
    expect(checkpointExcluded('distX/x', '.conatus', policy), isFalse);
    expect(checkpointExcluded('.opencode/x', '.conatus', policy), isFalse);
  });

  test('walk 剪掉只读目录；归档恢复不写回、不删除它', () async {
    final Directory dir = Directory.systemTemp.createTempSync(
      'conatus-cp-policy',
    );
    addTearDown(() => dir.deleteSync(recursive: true));
    final String root = dir.path;
    final String projectDir = '$root$_sep.conatus';
    Directory(projectDir).createSync();
    _write(root, '.opencode/keep.txt', 'orig');
    _write(root, 'a.txt', 'v0');

    final List<String> walked = <String>[
      await for (final FileSystemEntity entity in checkpointWalk(
        root,
        '.conatus',
        kReadOnlyProduct,
      ))
        checkpointRelativeTo(entity, root),
    ];
    expect(walked, contains('a.txt'));
    expect(walked, isNot(contains('.opencode/keep.txt')));
    expect(walked, isNot(contains('.conatus')));

    final ArchiveCheckpointStore store = ArchiveCheckpointStore(
      root: root,
      projectDir: projectDir,
      policy: kReadOnlyProduct,
    );
    await store.snapshot('s1', 0);
    _write(root, '.opencode/keep.txt', 'changed');
    _write(root, '.opencode/new.txt', 'added-after-snapshot');
    _write(root, 'a.txt', 'v1');

    await store.restore('s1', 0);

    expect(_read(root, '.opencode/keep.txt'), 'changed', reason: '只读目录不被写回');
    expect(
      _exists(root, '.opencode/new.txt'),
      isTrue,
      reason: '只读目录不被当成多余文件删除',
    );
    expect(_read(root, 'a.txt'), 'v0');
  });
}
