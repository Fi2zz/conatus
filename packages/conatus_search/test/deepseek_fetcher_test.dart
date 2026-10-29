import 'dart:convert';
import 'package:conatus_search/conatus_search.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

http.Response _json(String body, [int status = 200]) => http.Response(
      body,
      status,
      headers: const <String, String>{
        'content-type': 'application/json; charset=utf-8',
      },
    );

void main() {
  test('POST /v1/tools/fetch 并返回 markdown 正文', () async {
    http.Request? captured;
    final DeepSeekFetcher fetcher = DeepSeekFetcher(
      apiKey: 'sk-deepseek',
      client: MockClient((http.Request request) async {
        captured = request;
        return _json(jsonEncode(<String, Object?>{
          'title': 'Example',
          'content': '# Example\n\n正文。',
        }));
      }),
    );

    final FetchedPage page =
        await fetcher.fetch('https://e.com/a', format: FetchedFormat.markdown);

    expect(page.url, 'https://e.com/a');
    expect(page.content, '# Example\n\n正文。');
    expect(page.format, FetchedFormat.markdown);
    expect(captured!.method, 'POST');
    expect(captured!.url.toString(), '$kDeepSeekBaseUrl/v1/tools/fetch');
    expect(captured!.headers['authorization'], 'Bearer sk-deepseek');
    expect(jsonDecode(captured!.body),
        <String, Object?>{'url': 'https://e.com/a'});
  });

  test('请求 text/html 时如实标注为 markdown（上游只产出 markdown）', () async {
    final DeepSeekFetcher fetcher = DeepSeekFetcher(
      apiKey: 'k',
      client: MockClient((_) async => _json('{"content": "# T"}')),
    );

    for (final FetchedFormat format in <FetchedFormat>[
      FetchedFormat.text,
      FetchedFormat.html,
    ]) {
      final FetchedPage page =
          await fetcher.fetch('https://e.com', format: format);

      expect(page.format, FetchedFormat.markdown, reason: format.name);
      expect(page.content, '# T');
    }
  });

  test('按 maxChars 截断', () async {
    final DeepSeekFetcher fetcher = DeepSeekFetcher(
      apiKey: 'k',
      client: MockClient((_) async => _json('{"content": "abcdefgh"}')),
    );

    final FetchedPage page = await fetcher.fetch('https://e.com', maxChars: 4);

    expect(page.content, 'abcd');
  });

  test('content 缺失按空正文处理，类型不符抛 FetchException', () async {
    final DeepSeekFetcher empty = DeepSeekFetcher(
      apiKey: 'k',
      client: MockClient((_) async => _json('{"title": "T"}')),
    );
    expect((await empty.fetch('https://e.com')).content, '');

    final DeepSeekFetcher bad = DeepSeekFetcher(
      apiKey: 'k',
      client: MockClient((_) async => _json('{"content": 42}')),
    );
    await expectLater(
      bad.fetch('https://e.com'),
      throwsA(isA<FetchException>().having((FetchException e) => e.message,
          'message', 'deepseek 返回了非字符串的 content')),
    );
  });

  test('非 http(s) 链接在发请求前就拒绝', () async {
    final DeepSeekFetcher fetcher = DeepSeekFetcher(
      apiKey: 'k',
      client: MockClient((_) async {
        fail('不应发出请求');
      }),
    );

    for (final String url in <String>['ftp://e.com', 'https://', 'not a url']) {
      await expectLater(
        fetcher.fetch(url),
        throwsA(isA<FetchException>().having(
            (FetchException e) => e.message, 'message', contains('仅支持带主机名'))),
        reason: url,
      );
    }
  });

  test('404 带 error.message（取不到正文时可读原因）', () async {
    final DeepSeekFetcher fetcher = DeepSeekFetcher(
      apiKey: 'k',
      client: MockClient((_) async => _json(
            jsonEncode(<String, Object?>{
              'error': <String, Object?>{'message': 'unsupported content type'},
            }),
            404,
          )),
    );

    await expectLater(
      fetcher.fetch('https://e.com'),
      throwsA(isA<FetchException>().having((FetchException e) => e.message,
          'message', 'deepseek HTTP 404：unsupported content type')),
    );
  });

  test('错误体不是 JSON 时只报状态码', () async {
    final DeepSeekFetcher fetcher = DeepSeekFetcher(
      apiKey: 'k',
      client: MockClient((_) async => http.Response('<html>403</html>', 403)),
    );

    await expectLater(
      fetcher.fetch('https://e.com'),
      throwsA(isA<FetchException>().having(
          (FetchException e) => e.message, 'message', 'deepseek HTTP 403')),
    );
  });

  test('请求超时归一成 FetchException', () async {
    final DeepSeekFetcher fetcher = DeepSeekFetcher(
      apiKey: 'k',
      timeout: const Duration(milliseconds: 10),
      client: MockClient((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        return _json('{"content": "x"}');
      }),
    );

    await expectLater(
      fetcher.fetch('https://e.com'),
      throwsA(isA<FetchException>().having((FetchException e) => e.message,
          'message', contains('deepseek 请求超时'))),
    );
  });
}
