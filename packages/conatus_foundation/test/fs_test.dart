import 'dart:io';
import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

Matcher _fsError(FsErrorCode code) =>
    isA<FsError>().having((FsError e) => e.code, 'code', code);

void main() {
  late Directory dir;
  late LocalFileSystem fs;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('conatus-fs-test-');
    fs = LocalFileSystem(cwd: dir.path);
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  group('resolve / stat / lstat', () {
    test('resolve 相对路径并读取元数据', () async {
      File('${dir.path}/a.txt').writeAsStringSync('hi');
      final FsTarget target = await fs.resolve('a.txt');

      expect(target.displayPath, '${dir.path}/a.txt');
      final FsInfo info = (await fs.stat(target))!;
      expect(info.type, FsFileType.file);
      expect(info.size, 2);
    });

    test('stat 对不存在的目标返回 null', () async {
      final FsTarget target = await fs.resolve('missing.txt');
      expect(await fs.stat(target), isNull);
    });

    test('lstat 不跟随符号链接', () async {
      File('${dir.path}/target.txt').writeAsStringSync('t');
      Link('${dir.path}/link.txt').createSync('target.txt');

      final FsPathInfo info = (await fs.lstat('link.txt'))!;
      expect(info.type, FsFileType.symlink);
    });

    test('空路径抛 FS_NOT_FOUND', () async {
      await expectLater(
        fs.resolve('  '),
        throwsA(_fsError(FsErrorCode.notFound)),
      );
    });
  });

  group('readText', () {
    test('目录 → FS_NOT_REGULAR_FILE', () async {
      final FsTarget target = await fs.resolve('.');
      await expectLater(
        fs.readText(target),
        throwsA(_fsError(FsErrorCode.notRegularFile)),
      );
    });

    test('非 UTF-8 字节 → FS_NOT_TEXT', () async {
      File('${dir.path}/bin').writeAsBytesSync(<int>[0xff, 0xfe]);
      final FsTarget target = await fs.resolve('bin');
      await expectLater(
        fs.readText(target),
        throwsA(_fsError(FsErrorCode.notText)),
      );
    });
  });

  group('writeText', () {
    test('创建并读取，父目录自动补齐', () async {
      final FsTarget target = await fs.resolve('sub/new.txt');
      final FsWriteOutcome outcome = await fs.writeText(target, 'hello');

      expect(outcome.operation, FsWriteOperation.create);
      expect(outcome.before, isNull);
      expect(await fs.readText(target), 'hello');
    });

    test('覆盖携带 before 且 operation 为 update', () async {
      final FsTarget target = await fs.resolve('x.txt');
      await fs.writeText(target, 'one');
      final FsWriteOutcome second = await fs.writeText(target, 'two');

      expect(second.operation, FsWriteOperation.update);
      expect(second.before, 'one');
      expect(second.after, 'two');
    });

    test('createIfAbsent 拒绝已存在的目标', () async {
      final FsTarget target = await fs.resolve('x.txt');
      await fs.writeText(target, 'one');
      await expectLater(
        fs.writeText(target, 'two', expected: const FsCreateIfAbsent()),
        throwsA(_fsError(FsErrorCode.notObserved)),
      );
    });

    test('replaceIfVersion 拒绝过期版本、接受最新版本', () async {
      final FsTarget target = await fs.resolve('x.txt');
      final FsWriteOutcome first = await fs.writeText(target, 'one');

      await expectLater(
        fs.writeText(target, 'two',
            expected: const FsReplaceIfVersion('bogus')),
        throwsA(_fsError(FsErrorCode.staleVersion)),
      );
      final FsWriteOutcome ok = await fs.writeText(
        target,
        'two',
        expected: FsReplaceIfVersion(first.version),
      );
      expect(ok.after, 'two');
    });
  });

  group('editText', () {
    test('字面替换返回前后内容', () async {
      final FsTarget target = await fs.resolve('e.txt');
      await fs.writeText(target, 'hello world');

      final FsEditOutcome outcome = await fs.editText(
        target,
        const FsEditRequest(oldString: 'world', newString: 'conatus'),
      );

      expect(outcome.before, 'hello world');
      expect(outcome.after, 'hello conatus');
      expect(await fs.readText(target), 'hello conatus');
    });

    test('多处匹配未开 replaceAll → FS_AMBIGUOUS_EDIT', () async {
      final FsTarget target = await fs.resolve('e.txt');
      await fs.writeText(target, 'a a');
      await expectLater(
        fs.editText(
            target, const FsEditRequest(oldString: 'a', newString: 'b')),
        throwsA(_fsError(FsErrorCode.ambiguousEdit)),
      );
    });

    test('未找到 → FS_EDIT_NOT_FOUND', () async {
      final FsTarget target = await fs.resolve('e.txt');
      await fs.writeText(target, 'abc');
      await expectLater(
        fs.editText(
            target, const FsEditRequest(oldString: 'zzz', newString: '')),
        throwsA(_fsError(FsErrorCode.editNotFound)),
      );
    });

    test('版本守卫：过期版本 → FS_STALE_VERSION', () async {
      final FsTarget target = await fs.resolve('e.txt');
      await fs.writeText(target, 'abc');
      await expectLater(
        fs.editText(
          target,
          const FsEditRequest(oldString: 'abc', newString: 'x'),
          expectedVersion: 'bogus',
        ),
        throwsA(_fsError(FsErrorCode.staleVersion)),
      );
    });
  });

  group('remove', () {
    test('删除文件；目标不存在时静默', () async {
      final FsTarget target = await fs.resolve('gone.txt');
      await fs.writeText(target, 'x');

      await fs.remove(target);
      expect(await fs.stat(target), isNull);

      await fs.remove(target); // 幂等
      expect(await fs.stat(target), isNull);
    });
  });

  group('listDir / contains', () {
    test('按名稳定排序，目录不含内容读取', () async {
      File('${dir.path}/b.txt').writeAsStringSync('');
      File('${dir.path}/a.txt').writeAsStringSync('');
      Directory('${dir.path}/sub').createSync();

      final FsTarget target = await fs.resolve('.');
      final List<FsDirEntry> entries = await fs.listDir(target);

      expect(
        entries.map((FsDirEntry e) => e.name),
        <String>['a.txt', 'b.txt', 'sub'],
      );
      expect(entries[2].type, FsFileType.directory);
    });

    test('contains 判断父子包含关系', () async {
      final FsTarget root = await fs.resolve('.');
      final FsTarget child = await fs.resolve('a.txt');

      expect(fs.contains(root, child), isTrue);
      expect(fs.contains(child, root), isFalse);
    });
  });

  test('provideFileSystemLocal 作为 fs 服务提供', () {
    final ctx = Context.root();
    final FileSystem provided = provideFileSystemLocal(ctx);
    expect(provided, isA<LocalFileSystem>());
    expect(identical(ctx.require<FileSystem>('fs'), provided), isTrue);
    ctx.dispose();
  });
}
