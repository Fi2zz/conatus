import 'dart:io';

import 'package:conatus_search/conatus_search.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  test('抓取并去标签，格式为 text', () async {
    final HttpFetcher fetcher = HttpFetcher(
      client: MockClient((http.Request request) async => http.Response(
            '<html><body><script>bad()</script><p>Hello &amp; world</p></body></html>',
            200,
          )),
    );

    final FetchedPage page = await fetcher.fetch('https://e.com');

    expect(page.content, 'Hello & world');
    expect(page.format, FetchedFormat.text);
    expect(page.url, 'https://e.com');
  });

  test('按 maxChars 截断', () async {
    final HttpFetcher fetcher = HttpFetcher(
      client: MockClient(
          (http.Request request) async => http.Response('<p>abcdefghij</p>', 200)),
    );

    final FetchedPage page = await fetcher.fetch('https://e.com', maxChars: 5);

    expect(page.content, 'abcde');
  });

  test('非 200 抛 FetchException', () async {
    final HttpFetcher fetcher = HttpFetcher(
      client: MockClient((http.Request request) async => http.Response('', 404)),
    );

    await expectLater(
      fetcher.fetch('https://e.com'),
      throwsA(isA<FetchException>().having(
        (FetchException e) => e.message,
        'message',
        'HTTP 404',
      )),
    );
  });

  test('超时抛 FetchException', () async {
    final HttpFetcher fetcher = HttpFetcher(
      timeout: const Duration(milliseconds: 10),
      client: MockClient((http.Request request) async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        return http.Response('ok', 200);
      }),
    );

    await expectLater(
      fetcher.fetch('https://e.com'),
      throwsA(isA<FetchException>()),
    );
  });

  test('连接失败抛 FetchException 并带上原因', () async {
    final HttpFetcher fetcher = HttpFetcher(
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
    final HttpFetcher fetcher = HttpFetcher(
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
    final HttpFetcher fetcher = HttpFetcher(
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

  test('非法 URL 抛 FetchException', () async {
    final HttpFetcher fetcher = HttpFetcher(
      client:
          MockClient((http.Request request) async => http.Response('ok', 200)),
    );

    await expectLater(
      fetcher.fetch('not a url'),
      throwsA(isA<FetchException>()),
    );
  });

  test('缺主机名的 URL 抛 FetchException', () async {
    final HttpFetcher fetcher = HttpFetcher();

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

  test('stripHtml 去块、去标签、解码实体', () {
    expect(stripHtml('<style>x{}</style><div>a &lt;b&gt; c</div>'), 'a <b> c');
  });
}
