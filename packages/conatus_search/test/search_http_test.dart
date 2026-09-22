import 'dart:async';
import 'package:conatus_search/conatus_search.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

void main() {
  test('超时转成 SearchException，文案含 provider 名与秒数', () async {
    final Future<http.Response> slow = Future<http.Response>.delayed(
      const Duration(milliseconds: 100),
      () => http.Response('{}', 200),
    );

    await expectLater(
      sendWithTimeout(slow,
          timeout: const Duration(milliseconds: 10), provider: 'tavily'),
      throwsA(isA<SearchException>().having(
        (SearchException e) => e.message,
        'message',
        contains('tavily 请求超时'),
      )),
    );
  });

  test('未超时时原样返回响应', () async {
    final http.Response response = await sendWithTimeout(
      Future<http.Response>.value(http.Response('ok', 200)),
      timeout: const Duration(seconds: 5),
      provider: 'brave',
    );

    expect(response.statusCode, 200);
    expect(response.body, 'ok');
  });
}
