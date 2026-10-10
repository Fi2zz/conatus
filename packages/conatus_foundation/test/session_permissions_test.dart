/// E-13：会话 JSONL 落盘权限收紧为 0600（Windows 无 POSIX 权限位，跳过）。
library;

import 'dart:io';

import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:test/test.dart';

/// 取文件权限位（低 12 位，含 setuid/setgid/sticky）。
int _permissionBits(String path) => File(path).statSync().mode & 0xFFF;

SessionEvent _event() => SessionEvent.create(
      sessionId: 's1',
      type: 'user_message',
      seq: 0,
      time: DateTime(2024),
    );

void main() {
  late Directory dir;
  late JsonlSessionPersistence persistence;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('conatus-session-perm-');
    persistence = JsonlSessionPersistence(dir: dir.path);
  });

  tearDown(() => dir.deleteSync(recursive: true));

  test('首写后会话文件权限为 0600（不是 umask 的 0644）', () async {
    await persistence.append('s1', _event());

    expect(_permissionBits('${dir.path}/s1.jsonl'), 0x180); // 0o600
  }, testOn: '!windows');

  test('旧版本遗留的 0644 文件在本次追加时补收紧', () async {
    final File file = File('${dir.path}/s1.jsonl');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('{}' '\n');
    Process.runSync('chmod', <String>['644', file.path]);
    expect(_permissionBits(file.path), 0x1A4); // 0o644

    await persistence.append('s1', _event());

    expect(_permissionBits(file.path), 0x180);
  }, testOn: '!windows');

  test('收紧不阻断落盘：内容照常追加且可载回', () async {
    await persistence.append('s1', _event());
    await persistence.append(
      's1',
      SessionEvent.create(
        sessionId: 's1',
        type: 'assistant_message',
        seq: 1,
        time: DateTime(2024),
      ),
    );

    expect(
        (await persistence.load('s1')).map((SessionEvent e) => e.type),
        <String>[
          'user_message',
          'assistant_message',
        ]);
  });
}
