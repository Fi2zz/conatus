/// 快照采集的排除面：内置构建目录与宿主注入的全局只读目录。
library;

import 'package:conatus_checkpoint/conatus_checkpoint.dart';
import 'package:test/test.dart';

import 'checkpoint_fixtures.dart';

void main() {
  test('build/ .dart_tool/ node_modules/ .conatus/ 不进 base', () async {
    final (ArchiveCheckpointStore store, String root, _) = createArchiveStore();
    writeWorkspace(root, 'lib/main.dart', 'void main() {}');
    writeWorkspace(root, 'build/out.bin', 'artifact');
    writeWorkspace(root, '.dart_tool/x.json', '{}');
    writeWorkspace(root, 'node_modules/m/index.js', '1');
    writeWorkspace(root, '.conatus/local.state', 's');

    await store.snapshot('s1', 0);

    final CheckpointManifest manifest = store.manifestOf('s1', 0);
    expect(manifest.files.map((CheckpointFileEntry e) => e.path), <String>[
      'lib/main.dart',
    ]);
  });

  test('workdir 为 \$HOME 时全局 .config/opencode 不进快照', () {
    expect(
      checkpointExcluded(
        '.config${pathSep}opencode${pathSep}config.json',
        '.conatus',
        kProductPolicy,
      ),
      isTrue,
    );
    expect(
      checkpointExcluded(
        '.config${pathSep}other${pathSep}x.json',
        '.conatus',
        kProductPolicy,
      ),
      isFalse,
    );
  });
}
