import 'package:conatus_context/conatus_context.dart';
import 'package:test/test.dart';

void main() {
  test('JSON 数组识别为 jsonArray', () {
    expect(
      detectContent('[{"a":1},{"a":2},{"a":3}]').kind,
      ContentKind.jsonArray,
    );
  });

  test('BOM 开头的 JSON 数组仍识别为 jsonArray', () {
    expect(
      detectContent('\uFEFF[{"a":1},{"a":2},{"a":3}]').kind,
      ContentKind.jsonArray,
    );
  });

  test('pytest 日志识别为 buildLog', () {
    const String input = '=== FAILURES ===\n'
        'ERROR test_a.py::test_x - AssertionError\n'
        'Traceback (most recent call last):\n'
        '  File "test_a.py", line 3, in test_x\n'
        '2 failed, 100 passed in 1.2s\n';
    expect(detectContent(input).kind, ContentKind.buildLog);
  });

  test('npm 日志识别为 buildLog', () {
    const String input = 'npm ERR! code ELIFECYCLE\n'
        'npm ERR! errno 1\n'
        'npm WARN deprecated foo@1.0.0\n';
    expect(detectContent(input).kind, ContentKind.buildLog);
  });

  test('cargo 日志识别为 buildLog', () {
    const String input = 'error[E0425]: cannot find value `x`\n'
        ' --> src/main.rs:3:5\n'
        '  |\n'
        '3 |     x\n'
        '  |     ^ not found\n';
    expect(detectContent(input).kind, ContentKind.buildLog);
  });

  test('Unix 搜索行识别为 searchResults', () {
    const String input = 'lib/a.dart:12:foo\n'
        'lib/a.dart:13:bar\n'
        'lib/a.dart:14:baz\n';
    expect(detectContent(input).kind, ContentKind.searchResults);
  });

  test('Windows 路径与含连字符文件名识别为搜索结果', () {
    const String input = 'C:\\src\\pre-commit.dart:12:foo\n'
        'C:\\src\\pre-commit.dart:13:bar\n'
        'C:\\src\\pre-commit.dart:14:baz\n';
    expect(detectContent(input).kind, ContentKind.searchResults);
  });

  test('unified diff 识别为 diff', () {
    const String input = 'diff --git a/a.dart b/a.dart\n'
        '--- a/a.dart\n'
        '+++ b/a.dart\n'
        '@@ -1,3 +1,3 @@\n';
    expect(detectContent(input).kind, ContentKind.diff);
  });

  test('CSV 识别为 tabular', () {
    const String input = 'id,name\n1,a\n2,b\n3,c\n';
    expect(detectContent(input).kind, ContentKind.tabular);
  });

  test('markdown 表格识别为 tabular', () {
    const String input = '| id | name |\n'
        '|---|---|\n'
        '| 1 | a |\n';
    expect(detectContent(input).kind, ContentKind.tabular);
  });

  test('源码识别为 sourceCode', () {
    const String input = 'class A {\n'
        '  void f() {\n'
        '    return;\n'
        '  }\n'
        '}\n';
    expect(detectContent(input).kind, ContentKind.sourceCode);
  });

  test('git status 优先于其它信号', () {
    const String input = 'On branch main\n'
        'Changes not staged for commit:\n'
        '\tmodified:   lib/a.dart\n\n'
        'diff --git a/lib/a.dart b/lib/a.dart\n';
    expect(detectContent(input).kind, ContentKind.passthrough);
  });

  test('普通散文识别为 text', () {
    const String input = '今天天气不错，我们去公园散步。\n'
        '路上看到很多花，心情很好。\n';
    expect(detectContent(input).kind, ContentKind.text);
  });

  test('空串识别为 passthrough', () {
    expect(detectContent('').kind, ContentKind.passthrough);
    expect(detectContent('   \n').kind, ContentKind.passthrough);
  });
}
