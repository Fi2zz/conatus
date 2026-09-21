import 'dart:io';
import 'package:conatus_agent/conatus_agent.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_fs_tools/conatus_fs_tools.dart';
import 'package:test/test.dart';

import 'support/fake_shell.dart';

ToolContext _context(Map<String, Object?> args) =>
    ToolContext(ToolCall(name: 'rg', arguments: args));

const String _text = 'lib/a.dart:3:7: final x = 1;\n'
    'lib/b.dart:5:7: final y = 2;\n';

RipgrepTool _tool(FakeShellExecutor shell,
        {ToolResultEviction? eviction, int maxMatches = 1000}) =>
    RipgrepTool(
      shell: shell,
      binary: const RipgrepBinary(path: 'rg', source: RipgrepSource.system),
      eviction: eviction,
      maxMatches: maxMatches,
    );

ShellRunResult _run({
  int? exitCode,
  bool timedOut = false,
  String stdout = '',
  String stderr = '',
}) =>
    ShellRunResult(
      exitCode: exitCode,
      timedOut: timedOut,
      timeoutMs: 20000,
      stdout: CollectedOutput(text: stdout),
      stderr: CollectedOutput(text: stderr),
    );

void main() {
  group('RipgrepTool', () {
    test('exitCode == 1 → 无匹配', () async {
      final FakeShellExecutor shell = FakeShellExecutor(_run(exitCode: 1));

      final ToolResult result =
          await _tool(shell).call(_context(<String, Object?>{'pattern': 'zzz'}));

      expect(result.isError, isFalse);
      expect(result.content, '无匹配');
      expect((result.value! as Map<String, Object?>)['truncated'], isFalse);
    });

    test('exitCode == 0 → 透传原生 rg 文本输出', () async {
      final FakeShellExecutor shell = FakeShellExecutor(_run(exitCode: 0, stdout: _text));

      final ToolResult result =
          await _tool(shell).call(_context(<String, Object?>{'pattern': 'x'}));

      expect(result.isError, isFalse);
      expect(result.content, _text.trimRight());
    });

    test('构造参数：max-count / max-count-matches / -- 分隔', () async {
      final FakeShellExecutor shell = FakeShellExecutor(_run(exitCode: 1));

      await _tool(shell)
          .call(_context(<String, Object?>{'pattern': 'foo.*bar', 'path': 'lib'}));

      expect(shell.lastRequest!.command,
          "'rg' '--max-count' '50' '--max-count-matches' '1000' '--' 'foo.*bar' 'lib'");
    });

    test('type / context / limit 参数追加', () async {
      final FakeShellExecutor shell = FakeShellExecutor(_run(exitCode: 1));

      await _tool(shell).call(_context(<String, Object?>{
        'pattern': 'x',
        'type': 'dart',
        'context': 2,
        'limit': 10,
      }));

      expect(shell.lastRequest!.command, contains("'--type' 'dart'"));
      expect(shell.lastRequest!.command, contains("'-C' '2'"));
      expect(shell.lastRequest!.command, contains("'--max-count' '10'"));
    });

    test('exitCode != 0 → RG_ERROR', () async {
      final FakeShellExecutor shell =
          FakeShellExecutor(_run(exitCode: 2, stderr: 'boom'));

      final ToolResult result =
          await _tool(shell).call(_context(<String, Object?>{'pattern': 'x'}));

      expect(result.isError, isTrue);
      expect(result.error!.code, 'RG_ERROR');
      expect(result.content, contains('boom'));
    });

    test('timedOut → RG_TIMEOUT', () async {
      final FakeShellExecutor shell =
          FakeShellExecutor(_run(timedOut: true));

      final ToolResult result =
          await _tool(shell).call(_context(<String, Object?>{'pattern': 'x'}));

      expect(result.error!.code, 'RG_TIMEOUT');
    });

    test('files_only：带 --files-with-matches，返回文件名列表', () async {
      final FakeShellExecutor shell = FakeShellExecutor(
          _run(exitCode: 0, stdout: 'lib/a.dart\nlib/b.dart\n'));

      final ToolResult result = await _tool(shell).call(
          _context(<String, Object?>{'pattern': 'x', 'files_only': true}));

      expect(result.isError, isFalse);
      expect(shell.lastRequest!.command, contains('--files-with-matches'));
      expect(result.content, 'lib/a.dart\nlib/b.dart');
    });

    test('行数达硬上限时经 eviction 落盘并给预览', () async {
      final Directory dir = Directory.systemTemp.createTempSync('conatus-rg-evict-');
      final LocalFileSystem fs = LocalFileSystem(cwd: dir.path);
      final ToolResultEviction eviction =
          ToolResultEviction(fs: fs, threshold: 20, dir: dir.path);
      final FakeShellExecutor shell = FakeShellExecutor(_run(exitCode: 0, stdout: _text));

      final ToolResult result = await _tool(shell, eviction: eviction, maxMatches: 2)
          .call(_context(<String, Object?>{'pattern': 'x'}));

      expect(result.isError, isFalse);
      final Map<String, Object?> value = result.value! as Map<String, Object?>;
      expect(value['truncated'], isTrue);
      expect(value['spilled'], isTrue);
      final String spillPath = value['spillPath']! as String;
      expect(File(spillPath).existsSync(), isTrue);
      expect(File(spillPath).readAsStringSync(), _text.trimRight());
      expect(result.content, contains('完整内容已写入文件'));
      dir.deleteSync(recursive: true);
    });
  });
}
