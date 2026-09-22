import 'dart:convert';
import 'dart:io';

import 'package:conatus_search/conatus_search.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  test('POST /v1/scrape，解析 data.markdown，格式为 markdown', () async {
    http.Request? captured;
    final FirecrawlFetcher fetcher = FirecrawlFetcher(
      apiKey: 'fc-secret',
      client: MockClient((http.Request request) async {
        captured = request;
        return http.Response(
          jsonEncode(<String, Object?>{
            'success': true,
            'data': <String, Object?>{'markdown': '# 标题\n正文'},
          }),
          200,
          headers: <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        );
      }),
    );

    final FetchedPage page = await fetcher.fetch('https://e.com');

    expect(page.content, '# 标题\n正文');
    expect(page.format, FetchedFormat.markdown);
    expect(captured!.url.path, '/v1/scrape');
    expect(captured!.headers['authorization'], 'Bearer fc-secret');
    final Map<String, Object?> body =
        jsonDecode(captured!.body) as Map<String, Object?>;
    expect(body['url'], 'https://e.com');
    expect(body['formats'], <String>['markdown']);
  });

  test('按 maxChars 截断 markdown', () async {
    final FirecrawlFetcher fetcher = FirecrawlFetcher(
      apiKey: 'k',
      client: MockClient((http.Request request) async => http.Response(
            '{"success": true, "data": {"markdown": "abcdefghij"}}',
            200,
          )),
    );

    final FetchedPage page = await fetcher.fetch('https://e.com', maxChars: 4);

    expect(page.content, 'abcd');
  });

  test('success:false 抛 FetchException 并带上原因', () async {
    final FirecrawlFetcher fetcher = FirecrawlFetcher(
      apiKey: 'k',
      client: MockClient((http.Request request) async => http.Response(
            '{"success": false, "error": "Blocked"}',
            200,
          )),
    );

    await expectLater(
      fetcher.fetch('https://e.com'),
      throwsA(isA<FetchException>().having(
        (FetchException e) => e.message,
        'message',
        contains('Blocked'),
      )),
    );
  });

  test('非 200 抛 FetchException', () async {
    final FirecrawlFetcher fetcher = FirecrawlFetcher(
      apiKey: 'k',
      client: MockClient(
          (http.Request request) async => http.Response('{}', 402)),
    );

    await expectLater(
      fetcher.fetch('https://e.com'),
      throwsA(isA<FetchException>().having(
        (FetchException e) => e.message,
        'message',
        'Firecrawl HTTP 402',
      )),
    );
  });

  test('超时抛 FetchException', () async {
    final FirecrawlFetcher fetcher = FirecrawlFetcher(
      apiKey: 'k',
      timeout: const Duration(milliseconds: 10),
      client: MockClient((http.Request request) async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        return http.Response('{}', 200);
      }),
    );

    await expectLater(
      fetcher.fetch('https://e.com'),
      throwsA(isA<FetchException>().having(
        (FetchException e) => e.message,
        'message',
        contains('超时'),
      )),
    );
  });

  test('连接失败抛 FetchException 并带上原因', () async {
    final FirecrawlFetcher fetcher = FirecrawlFetcher(
      apiKey: 'k',
      client: MockClient((http.Request request) async =>
          throw http.ClientException('connection refused')),
    );

    await expectLater(
      fetcher.fetch('https://e.com'),
      throwsA(isA<FetchException>().having(
        (FetchException e) => e.message,
        'message',
        contains('connection refused'),
      )),
    );
  });

  test('socket 失败抛 FetchException', () async {
    final FirecrawlFetcher fetcher = FirecrawlFetcher(
      apiKey: 'k',
      client: MockClient((http.Request request) async =>
          throw const SocketException('host unreachable')),
    );

    await expectLater(
      fetcher.fetch('https://e.com'),
      throwsA(isA<FetchException>().having(
        (FetchException e) => e.message,
        'message',
        contains('host unreachable'),
      )),
    );
  });

  test('TLS 握手失败抛 FetchException', () async {
    final FirecrawlFetcher fetcher = FirecrawlFetcher(
      apiKey: 'k',
      client: MockClient((http.Request request) async =>
          throw const HandshakeException('certificate verify failed')),
    );

    await expectLater(
      fetcher.fetch('https://e.com'),
      throwsA(isA<FetchException>().having(
        (FetchException e) => e.message,
        'message',
        contains('certificate verify failed'),
      )),
    );
  });

  test('非法 URL 抛 FetchException 且不发请求', () async {
    var sent = false;
    final FirecrawlFetcher fetcher = FirecrawlFetcher(
      apiKey: 'k',
      client: MockClient((http.Request request) async {
        sent = true;
        return http.Response('{}', 200);
      }),
    );

    await expectLater(
      fetcher.fetch('not a url'),
      throwsA(isA<FetchException>()),
    );
    expect(sent, isFalse);
  });

  test('缺主机名的 URL 抛 FetchException', () async {
    final FirecrawlFetcher fetcher = FirecrawlFetcher(
      apiKey: 'k',
      client:
          MockClient((http.Request request) async => http.Response('{}', 200)),
    );

    for (final String url in <String>['http://', 'https:///x']) {
      await expectLater(
        fetcher.fetch(url),
        throwsA(isA<FetchException>().having(
          (FetchException e) => e.message,
          'message',
          contains('主机名'),
        )),
      );
    }
  });

  test('响应缺少 data 抛 FetchException', () async {
    final FirecrawlFetcher fetcher = FirecrawlFetcher(
      apiKey: 'k',
      client: MockClient((http.Request request) async =>
          http.Response('{"success": true}', 200)),
    );

    await expectLater(
      fetcher.fetch('https://e.com'),
      throwsA(isA<FetchException>().having(
        (FetchException e) => e.message,
        'message',
        contains('data'),
      )),
    );
  });

  test('Firecrawl 凭据键名固定', () {
    expect(kFirecrawlCredentialKey, 'FIRECRAWL_API_KEY');
  });
}
