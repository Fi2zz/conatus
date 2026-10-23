import 'package:conatus_skill/conatus_skill.dart';
import 'package:test/test.dart';

void main() {
  group('解析成功', () {
    test('parses fields and body', () {
      final FrontmatterDocument doc = parseFrontmatter(
        '---\ndescription: review\nmode: subagent\n---\nBody here\n',
      );
      expect(doc.fields['description'], 'review');
      expect(doc.fields['mode'], 'subagent');
      expect(doc.body, 'Body here');
      expect(doc.error, isNull);
    });

    test('不需要 name / description', () {
      final FrontmatterDocument doc =
          parseFrontmatter('---\nfoo: bar\n---\n正文');

      expect(doc.error, isNull);
      expect(doc.fields, <String, Object?>{'foo': 'bar'});
    });

    test('保留嵌套映射、数字与布尔值', () {
      final FrontmatterDocument doc = parseFrontmatter('---\n'
          'model: fast\n'
          'steps: 3\n'
          'hidden: true\n'
          'metadata:\n'
          '  owner: platform\n'
          '  tags:\n'
          '    - a\n'
          '    - b\n'
          '---\n'
          'body');

      expect(doc.error, isNull);
      expect(doc.fields['steps'], 3);
      expect(doc.fields['hidden'], isTrue);
      expect(doc.fields['metadata'], <String, Object?>{
        'owner': 'platform',
        'tags': <Object?>['a', 'b'],
      });
    });

    test('正文两侧空白被 trim，内部换行保留', () {
      final FrontmatterDocument doc = parseFrontmatter(
        '---\na: b\n---\n\n  第一行。\n\n第二行。  \n',
      );

      expect(doc.body, '第一行。\n\n第二行。');
    });

    test('闭合行之后没有正文时 body 为空串', () {
      expect(parseFrontmatter('---\na: b\n---\n').body, isEmpty);
    });

    test('CRLF 文本同样能解析', () {
      final FrontmatterDocument doc = parseFrontmatter(
        '---\r\ndescription: CRLF 说明\r\nmode: subagent\r\n---\r\n\r\n正文。\r\n',
      );

      expect(doc.error, isNull);
      expect(doc.fields['description'], 'CRLF 说明');
      expect(doc.fields['mode'], 'subagent');
      expect(doc.body, '正文。');
    });

    test('UTF-8 中文与 emoji 原样保留', () {
      final FrontmatterDocument doc = parseFrontmatter(
        '---\ndescription: 审查 🚀 代码\n---\n正文含中文、emoji 🎯 与符号 ✓\n',
      );

      expect(doc.error, isNull);
      expect(doc.fields['description'], '审查 🚀 代码');
      expect(doc.body, '正文含中文、emoji 🎯 与符号 ✓');
    });
  });

  group('解析失败', () {
    test('missing closing fence returns error', () {
      expect(parseFrontmatter('---\na: b\nbody').error, contains('缺少'));
    });

    test('缺闭合 --- 时 fields 为空、body 为空', () {
      final FrontmatterDocument doc = parseFrontmatter('---\na: b\nbody');

      expect(doc.error, isNotNull);
      expect(doc.fields, isEmpty);
      expect(doc.body, isEmpty);
    });

    test('首行不是 --- 时报错，正文尽力保留', () {
      final FrontmatterDocument doc =
          parseFrontmatter('description: 说明\n\n正文。\n');

      expect(doc.error, contains('缺少'));
      expect(doc.fields, isEmpty);
      expect(doc.body, 'description: 说明\n\n正文。');
    });

    test('非法 YAML 时报错并保留正文', () {
      final FrontmatterDocument doc =
          parseFrontmatter('---\ndescription: "未闭合\n---\n正文。');

      expect(doc.error, contains('不是合法 YAML'));
      expect(doc.fields, isEmpty);
      expect(doc.body, '正文。');
    });

    test('frontmatter 不是键值映射时报错', () {
      for (final String source in <String>[
        '---\n- a\n- b\n---\n正文',
        '---\njust-a-string\n---\n正文',
      ]) {
        final FrontmatterDocument doc = parseFrontmatter(source);
        expect(doc.error, contains('必须是键值映射'), reason: source);
        expect(doc.fields, isEmpty, reason: source);
        expect(doc.body, '正文', reason: source);
      }
    });

    test('空 frontmatter 块视为非映射', () {
      expect(parseFrontmatter('---\n---\n正文').error, contains('必须是键值映射'));
    });
  });
}
