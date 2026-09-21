/// registry 导入：正文解析与拉取。
library;

import 'dart:convert';

import 'package:conatus_providers/conatus_providers.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  test('解析 {providers: [...]}', () {
    final List<ProviderProfile> parsed =
        parseProviderRegistry(jsonEncode(<String, Object?>{
      'providers': <Map<String, Object?>>[
        <String, Object?>{
          'name': 'p1',
          'baseUrl': 'https://p1/v1',
          'credentialKey': 'P1_KEY',
          'models': <String>['m1', 'm2'],
        },
      ],
    }));

    expect(parsed.single.name, 'p1');
    expect(parsed.single.credentialKey, 'P1_KEY');
    expect(parsed.single.defaultModel, 'm1');
  });

  test('userAgent 字段随 JSON 往返', () {
    final ProviderProfile parsed = parseProviderRegistry(jsonEncode(<Map<String, Object?>>[
      <String, Object?>{
        'name': 'dsh',
        'baseUrl': 'https://api.deepseek.example/v1',
        'userAgent': 'dsh/0.1.2',
      },
    ])).single;
    expect(parsed.userAgent, 'dsh/0.1.2');
    expect(parsed.toJson()['userAgent'], 'dsh/0.1.2');

    final ProviderProfile plain = parseProviderRegistry(jsonEncode(
        <Map<String, Object?>>[
          <String, Object?>{'name': 'p', 'baseUrl': 'https://p'},
        ])).single;
    expect(plain.userAgent, '');
    expect(plain.toJson().containsKey('userAgent'), isFalse);
  });

  test('解析顶层数组', () {
    final List<ProviderProfile> parsed =
        parseProviderRegistry(jsonEncode(<Map<String, Object?>>[
      <String, Object?>{'name': 'p', 'baseUrl': 'https://p'},
    ]));

    expect(parsed.single.name, 'p');
    expect(parsed.single.models, isEmpty);
  });

  test('结构不符抛 FormatException', () {
    expect(() => parseProviderRegistry('{"x": 1}'), throwsFormatException);
    expect(() => parseProviderRegistry('{"providers": [{}]}'),
        throwsFormatException);
  });

  test('fetch 带 Bearer 并解析', () async {
    final MockClient client = MockClient((http.Request request) async {
      expect(request.headers['Authorization'], 'Bearer tok');
      return http.Response(
        jsonEncode(<String, Object?>{
          'providers': <Map<String, Object?>>[
            <String, Object?>{'name': 'p', 'baseUrl': 'https://p'},
          ],
        }),
        200,
      );
    });

    final ProviderImportResult result = await fetchProviderRegistry(
      url: 'https://registry.example/api.json',
      token: 'tok',
      client: client,
    );

    expect(result.isSuccess, isTrue);
    expect(result.providers.single.name, 'p');
  });

  test('非 200、非法 URL、空列表都是失败结果', () async {
    final MockClient failing =
        MockClient((http.Request request) async => http.Response('nope', 500));

    expect(
      (await fetchProviderRegistry(
              url: 'https://x/api.json', token: '', client: failing))
          .error,
      contains('500'),
    );
    expect(
      (await fetchProviderRegistry(url: 'not a url', token: '')).error,
      'URL 不合法',
    );
    expect(
      (await fetchProviderRegistry(
              url: 'https://x/api.json',
              token: '',
              client: _clientOf(<String, Object?>{'providers': <Object?>[]})))
          .error,
      contains('没有 provider'),
    );
  });
}

/// 固定返回 [body] 的假 client。
MockClient _clientOf(Object? body) =>
    MockClient((http.Request request) async => http.Response(jsonEncode(body), 200));
