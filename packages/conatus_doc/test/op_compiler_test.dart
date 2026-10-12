import 'package:conatus_doc/conatus_doc.dart';
import 'package:test/test.dart';

void main() {
  group('compileOpsBlock', () {
    test('从完整文本编译 ops 块', () {
      final List<PatchOp> ops = compileOpsBlock(
        '草稿如下：```ops\n'
        '[{"kind":"insert","blockId":"b1","text":"一"},'
        '{"kind":"replace","blockId":"b0","text":"零"}]\n'
        '```\n以上。',
      );
      expect(ops, hasLength(2));
      expect(ops.first, isA<InsertBlockOp>());
      expect(ops.last, isA<ReplaceBlockOp>());
    });

    test('无 ops 块返回空列表', () {
      expect(compileOpsBlock('只是普通回复。'), isEmpty);
    });

    test('块体非 JSON 数组抛 FormatException', () {
      expect(
          () => compileOpsBlock('```ops\n{"a":1}\n```'), throwsFormatException);
    });

    test('未知 op kind 抛 ArgumentError', () {
      expect(
        () =>
            compileOpsBlock('```ops\n[{"kind":"teleport","blockId":"b"}]\n```'),
        throwsArgumentError,
      );
    });
  });

  group('OpStreamCompiler（流式）', () {
    test('围栏与 JSON 跨段拆分也能编译', () {
      final OpStreamCompiler compiler = OpStreamCompiler();
      expect(compiler.feed('起稿。``'), isEmpty);
      expect(compiler.feed('`ops\n[{"kind":"ins'), isEmpty);
      final List<PatchOp> ops = compiler.feed(
        'ert","blockId":"b1","text":"一"}]\n`',
      );
      expect(ops, isEmpty); // 闭围栏未到齐
      expect(compiler.feed('``'), hasLength(1));
      expect(ops, isEmpty);
    });

    test('多个 ops 块逐块产出', () {
      final OpStreamCompiler compiler = OpStreamCompiler();
      final List<PatchOp> first = compiler.feed(
        '```ops\n[{"kind":"insert","blockId":"b1","text":"一"}]\n```',
      );
      final List<PatchOp> second = compiler.feed(
        '中段文字```ops\n[{"kind":"remove","blockId":"b1"}]\n```',
      );
      expect(first.single, isA<InsertBlockOp>());
      expect(second.single, isA<RemoveBlockOp>());
    });
  });
}
