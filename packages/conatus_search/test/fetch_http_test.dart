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

  test('stripHtml 去块、去标签、解码实体', () {
    expect(stripHtml('<style>x{}</style><div>a &lt;b&gt; c</div>'), 'a <b> c');
  });
}
