import 'package:conatus_skill/conatus_skill.dart';
import 'package:test/test.dart';

String skillText(String frontmatter, {String body = '正文。'}) =>
    '---\n$frontmatter\n---\n\n$body\n';

SkillDocument parseOf(String frontmatter, {String body = '正文。'}) =>
    parseSkillDocument(skillText(frontmatter, body: body));

String? errorOf(String frontmatter) => parseOf(frontmatter).error;

void main() {
  group('解析成功', () {
    test('frontmatter 齐全时逐字段读出，正文被 trim', () {
      final SkillDocument document = parseSkillDocument('---\n'
          'name: release-notes\n'
          'description: 把一组合并记录改写成发布说明\n'
          'whenToUse: 用户提到 changelog 时\n'
          'metadata:\n'
          '  owner: platform\n'
          '  weight: 3\n'
          '---\n'
          '\n'
          '  先读 docs/release.md。\n'
          '\n'
          '再写发布说明。  \n');

      expect(document.error, isNull);
      final SkillFrontmatter? frontmatter = document.frontmatter;
      expect(frontmatter?.name, 'release-notes');
      expect(frontmatter?.description, '把一组合并记录改写成发布说明');
      expect(frontmatter?.whenToUse, '用户提到 changelog 时');
      expect(frontmatter?.metadata, <String, Object?>{
        'owner': 'platform',
        'weight': 3,
      });
      expect(frontmatter?.modelInvocable, isTrue);
      expect(document.body, '先读 docs/release.md。\n\n再写发布说明。');
    });

    test('可选字段缺省时为空，description 两侧空白被去掉', () {
      final SkillDocument document = parseOf(
        'name: alpha\n'
        'description: "  带空白的一行  "',
      );

      expect(document.error, isNull);
      expect(document.frontmatter?.description, '带空白的一行');
      expect(document.frontmatter?.whenToUse, isNull);
      expect(document.frontmatter?.metadata, isNull);
    });

    test('闭合行之后没有正文时 body 为空串', () {
      final SkillDocument document = parseSkillDocument(
        '---\nname: alpha\ndescription: 说明\n---\n',
      );

      expect(document.error, isNull);
      expect(document.body, isEmpty);
    });

    test('CRLF 文本同样能解析', () {
      final SkillDocument document = parseSkillDocument(
        '---\r\n'
        'name: alpha\r\n'
        'description: CRLF 说明\r\n'
        '---\r\n'
        '\r\n'
        '正文第一行。\r\n',
      );

      expect(document.error, isNull);
      expect(document.frontmatter?.name, 'alpha');
      expect(document.frontmatter?.description, 'CRLF 说明');
      expect(document.body, '正文第一行。');
    });
  });

  group('frontmatter 形状', () {
    test('没有 frontmatter 时整条丢弃', () {
      final SkillDocument document =
          parseSkillDocument('name: alpha\ndescription: 说明\n');

      expect(document.error, isNotNull);
      expect(document.frontmatter, isNull);
      expect(document.body, isEmpty);
    });

    test('缺闭合 --- 时整条丢弃', () {
      expect(
        parseSkillDocument('---\nname: alpha\ndescription: 说明\n正文。').error,
        isNotNull,
      );
    });

    test('frontmatter 不是键值映射时整条丢弃', () {
      expect(parseSkillDocument('---\n- a\n- b\n---\n正文').error, isNotNull);
      expect(
          parseSkillDocument('---\njust-a-string\n---\n正文').error, isNotNull);
    });

    test('frontmatter 不是合法 YAML 时整条丢弃', () {
      expect(errorOf('name: alpha\ndescription: "未闭合'), isNotNull);
    });
  });

  group('字段校验', () {
    test('缺 name 时整条丢弃', () {
      expect(errorOf('description: 说明'), isNotNull);
    });

    test('name 不是 kebab-case 时整条丢弃', () {
      for (final String name in <String>[
        'Foo',
        'foo_bar',
        'foo--bar',
        'foo-',
        '-foo',
        'FOO',
      ]) {
        final SkillDocument document = parseOf('name: $name\ndescription: 说明');
        expect(document.error, isNotNull, reason: name);
        expect(document.frontmatter, isNull, reason: name);
      }
    });

    test('description 缺失或为空时整条丢弃', () {
      expect(errorOf('name: alpha'), isNotNull);
      expect(errorOf("name: alpha\ndescription: ''"), isNotNull);
      expect(errorOf('name: alpha\ndescription: "   "'), isNotNull);
    });
  });

  group('布尔文法', () {
    test('真值写法都让技能对模型隐藏', () {
      for (final String raw in <String>[
        'true',
        'True',
        'TRUE',
        'tRuE',
        'yes',
        'Yes',
        'yEs',
        'on',
        'On',
        'oN',
        '1',
        "'true'",
        "'YES'",
      ]) {
        final SkillDocument document = parseOf(
          'name: alpha\ndescription: 说明\ndisable-model-invocation: $raw',
        );
        expect(document.error, isNull, reason: raw);
        expect(document.frontmatter?.modelInvocable, isFalse, reason: raw);
      }
    });

    test('假值写法都让技能保持可调用', () {
      for (final String raw in <String>[
        'false',
        'False',
        'FALSE',
        'fAlSe',
        'no',
        'No',
        'off',
        'OFF',
        'oFf',
        '0',
        "'false'",
        "'off'",
      ]) {
        final SkillDocument document = parseOf(
          'name: alpha\ndescription: 说明\ndisable-model-invocation: $raw',
        );
        expect(document.error, isNull, reason: raw);
        expect(document.frontmatter?.modelInvocable, isTrue, reason: raw);
      }
    });

    test('缺省时可调用', () {
      expect(
          parseOf('name: alpha\ndescription: 说明').frontmatter?.modelInvocable,
          isTrue);
    });

    test('非法布尔值让整条丢弃', () {
      for (final String raw in <String>['maybe', '2', '[1]', '{}']) {
        expect(
          errorOf(
              'name: alpha\ndescription: 说明\ndisable-model-invocation: $raw'),
          isNotNull,
          reason: raw,
        );
      }
    });
  });

  group('旧键', () {
    test('camelCase 键让整条丢弃并指明键名', () {
      for (final String legacy in kSkillLegacyFrontmatterKeys) {
        final SkillDocument document = parseOf(
          'name: alpha\ndescription: 说明\n$legacy: true',
        );
        expect(document.error, isNotNull, reason: legacy);
        expect(document.error, contains(legacy), reason: legacy);
        expect(document.frontmatter, isNull, reason: legacy);
      }
    });
  });

  group('技能名校验', () {
    test('小写字母数字与单个连字符通过', () {
      for (final String name in <String>[
        'a',
        'a-b',
        'a1-b2',
        'release-notes',
        '9',
      ]) {
        expect(isSkillName(name), isTrue, reason: name);
      }
    });

    test('大写、空串、下划线、首尾或连续连字符都不通过', () {
      for (final String name in <String>[
        'A',
        '-a',
        'a-',
        'a_b',
        'a--b',
        '',
        'a b',
        'a-1-',
      ]) {
        expect(isSkillName(name), isFalse, reason: name);
      }
    });
  });
}
