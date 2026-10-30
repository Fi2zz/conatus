/// 通用只读路径闸门：写/删在受保护根下一律拒绝，读全部透传。
library;

import 'dart:io';

import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;
  late ReadOnlyPathGuard guard;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('ro-guard-');
    Directory('${dir.path}/.opencode/commands').createSync(recursive: true);
    File('${dir.path}/.opencode/commands/x.md').writeAsStringSync('before');
    guard = ReadOnlyPathGuard(
      inner: LocalFileSystem(),
      protectedRoots: <String>['${dir.path}/.opencode'],
    );
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('write under .opencode is denied', () async {
    final FsTarget target = await guard.resolve(
      '${dir.path}/.opencode/commands/new.md',
    );
    expect(
      () => guard.writeText(target, 'x'),
      throwsA(
        isA<FsError>().having(
          (FsError e) => e.message,
          'message',
          contains('READ_ONLY_PATH'),
        ),
      ),
    );
    expect(File('${dir.path}/.opencode/commands/new.md').existsSync(), isFalse);
  });

  test('edit under .opencode is denied and bytes stay unchanged', () async {
    final FsTarget target = await guard.resolve(
      '${dir.path}/.opencode/commands/x.md',
    );
    expect(
      () => guard.editText(
        target,
        const FsEditRequest(oldString: 'before', newString: 'after'),
      ),
      throwsA(isA<FsError>()),
    );
    expect(
      File('${dir.path}/.opencode/commands/x.md').readAsStringSync(),
      'before',
    );
  });

  test('remove of .opencode entry and of the root itself is denied', () async {
    final FsTarget file = await guard.resolve(
      '${dir.path}/.opencode/commands/x.md',
    );
    expect(() => guard.remove(file), throwsA(isA<FsError>()));
    final FsTarget root = await guard.resolve('${dir.path}/.opencode');
    expect(() => guard.remove(root), throwsA(isA<FsError>()));
    expect(File('${dir.path}/.opencode/commands/x.md').existsSync(), isTrue);
  });

  test('remove of an ancestor containing .opencode is denied', () async {
    final FsTarget workspace = await guard.resolve(dir.path);

    expect(() => guard.remove(workspace), throwsA(isA<FsError>()));
    expect(
      File('${dir.path}/.opencode/commands/x.md').existsSync(),
      isTrue,
      reason: '删除工作区不能连带删掉受保护目录',
    );

    // 不含受保护根的同级目录照常可删。
    final Directory spare = Directory('${dir.path}/spare')..createSync();
    final FsTarget spareTarget = await guard.resolve(spare.path);
    await guard.remove(spareTarget);
    expect(spare.existsSync(), isFalse);
  });

  test('normalizeReadOnlyPath 不改变盘符绝对路径的形状', () {
    final String sep = Platform.pathSeparator;
    expect(normalizeReadOnlyPath(r'C:\foo\bar'), 'C:${sep}foo${sep}bar');
    expect(normalizeReadOnlyPath('C:rel'), 'C:rel');
  });

  test('reads pass through untouched', () async {
    final FsTarget target = await guard.resolve(
      '${dir.path}/.opencode/commands/x.md',
    );
    expect(await guard.readText(target), 'before');
    expect((await guard.stat(target))?.size, 6);
    expect(
      (await guard.listDir(
        await guard.resolve('${dir.path}/.opencode'),
      ))
          .map((FsDirEntry e) => e.name),
      contains('commands'),
    );
    expect(guard.processPath(target), contains('.opencode'));
    expect(guard.fileUrl(target), startsWith('file:'));
    expect(await guard.lstat('${dir.path}/.opencode'), isNotNull);
  });

  test('writes outside protected roots still work', () async {
    final FsTarget target = await guard.resolve('${dir.path}/notes.txt');
    await guard.writeText(target, 'ok');
    expect(File('${dir.path}/notes.txt').readAsStringSync(), 'ok');
    await guard.editText(
      target,
      const FsEditRequest(oldString: 'ok', newString: 'ok2'),
    );
    expect(File('${dir.path}/notes.txt').readAsStringSync(), 'ok2');
    await guard.remove(target);
    expect(File('${dir.path}/notes.txt').existsSync(), isFalse);
    // 受保护根同级的相似名不受影响。
    final FsTarget sibling = await guard.resolve(
      '${dir.path}/.opencode-backup/x.md',
    );
    await guard.writeText(sibling, 'ok');
    expect(File('${dir.path}/.opencode-backup/x.md').existsSync(), isTrue);
  });

  test('symlink under .opencode cannot write outside', () async {
    final Directory outside = Directory.systemTemp.createTempSync('ro-out-');
    addTearDown(() {
      if (outside.existsSync()) outside.deleteSync(recursive: true);
    });
    Directory('${outside.path}/target').createSync(recursive: true);
    Link('${dir.path}/.opencode/escape').createSync('${outside.path}/target');

    final FsTarget target = await guard.resolve(
      '${dir.path}/.opencode/escape/x',
    );
    expect(() => guard.writeText(target, 'x'), throwsA(isA<FsError>()));
    expect(File('${outside.path}/target/x').existsSync(), isFalse);
  });

  test('workdir 是符号链接别名 + .opencode 尚未创建 → 仍然拒绝', () async {
    final Directory real = Directory.systemTemp.createTempSync('ro-real-');
    addTearDown(() {
      if (real.existsSync()) real.deleteSync(recursive: true);
    });
    final String alias = '${dir.path}/alias';
    Link(alias).createSync(real.path);
    final String canonical = real.resolveSymbolicLinksSync();
    // 与 CLI 一致：fs 根用规范拼写（macOS /var → /private/var），受保护根用
    // 用户传入的字面 workdir 别名——两种拼写不同，且 .opencode 还不存在。
    final ReadOnlyPathGuard aliasGuard = ReadOnlyPathGuard(
      inner: LocalFileSystem(cwd: canonical),
      protectedRoots: <String>['$alias/.opencode'],
    );

    final FsTarget target = await aliasGuard.resolve('.opencode/commands/x.md');

    expect(aliasGuard.processPath(target), startsWith(canonical));
    expect(() => aliasGuard.writeText(target, 'x'), throwsA(isA<FsError>()));
    expect(Directory('$canonical/.opencode').existsSync(), isFalse);
  });

  test('jail 后端（规范根）+ 字面 workdir + 未创建 → 拒绝', () async {
    final Directory jail = Directory('${dir.path}/jail')..createSync();
    final String canonical = jail.resolveSymbolicLinksSync();
    final ReadOnlyPathGuard jailGuard = ReadOnlyPathGuard(
      inner: LocalFileSystem(cwd: canonical),
      protectedRoots: <String>['${jail.path}/.opencode'],
    );

    final FsTarget target = await jailGuard.resolve(
      '.opencode/commands/x.md',
      cwd: canonical,
    );

    expect(() => jailGuard.writeText(target, 'x'), throwsA(isA<FsError>()));
    expect(Directory('$canonical/.opencode').existsSync(), isFalse);
  });

  test('deniedMessage 可注入', () async {
    final ReadOnlyPathGuard custom = ReadOnlyPathGuard(
      inner: LocalFileSystem(),
      protectedRoots: <String>['${dir.path}/.opencode'],
      deniedMessage: 'APP_CONFIG_READ_ONLY',
    );
    final FsTarget target = await custom.resolve('${dir.path}/.opencode/x');
    expect(
      () => custom.writeText(target, 'x'),
      throwsA(
        isA<FsError>().having(
          (FsError e) => e.message,
          'message',
          contains('APP_CONFIG_READ_ONLY'),
        ),
      ),
    );
  });
}
