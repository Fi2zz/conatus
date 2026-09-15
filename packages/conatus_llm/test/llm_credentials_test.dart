import 'dart:convert';
import 'dart:io';

import 'package:conatus_credentials/conatus_credentials.dart';
import 'package:conatus_llm/conatus_llm.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

/// 记录每次请求 `Authorization` 头的假客户端。
class _Recorder {
  final List<String> authorizations = <String>[];

  MockClient get client => MockClient((http.Request request) async {
        authorizations.add(request.headers['Authorization'] ?? '');
        return http.Response(
          jsonEncode(<String, dynamic>{
            'id': 'chatcmpl-test',
            'object': 'chat.completion',
            'model': 'doubao-seed-1-8-251228',
            'choices': <dynamic>[
              <String, dynamic>{
                'index': 0,
                'message': <String, dynamic>{
                  'role': 'assistant',
                  'content': 'ok',
                },
                'finish_reason': 'stop',
              },
            ],
          }),
          200,
          headers: <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
        );
      });

  String get last => authorizations.isEmpty ? '' : authorizations.last;
}

void main() {
  final List<LlmMessage> messages = <LlmMessage>[
    const LlmMessage('user', 'hi'),
  ];

  test('构造期从 credentials 同步取 Key', () async {
    final _Recorder recorder = _Recorder();
    final InMemoryCredentials credentials = InMemoryCredentials(
      initial: <String, String>{'ARK_API_KEY': 'from-store'},
    );
    final DoubaoProvider provider = DoubaoProvider(
      credentials: credentials,
      client: recorder.client,
    );

    await provider.chat(messages);
    expect(recorder.last, 'Bearer from-store');

    provider.close();
    credentials.close();
  });

  test('凭据轮换后下一次请求用新值', () async {
    final _Recorder recorder = _Recorder();
    final InMemoryCredentials credentials = InMemoryCredentials(
      initial: <String, String>{'ARK_API_KEY': 'old-key'},
    );
    final DoubaoProvider provider = DoubaoProvider(
      credentials: credentials,
      client: recorder.client,
    );
    await provider.chat(messages);
    expect(recorder.last, 'Bearer old-key');

    await credentials.update('ARK_API_KEY', 'new-key');
    await pumpEventQueue();
    await provider.chat(messages);
    expect(recorder.last, 'Bearer new-key');

    provider.close();
    credentials.close();
  });

  test('只对匹配的凭据键轮换', () async {
    final _Recorder recorder = _Recorder();
    final InMemoryCredentials credentials = InMemoryCredentials(
      initial: <String, String>{'ARK_API_KEY': 'ark-key'},
    );
    final DoubaoProvider provider = DoubaoProvider(
      credentials: credentials,
      client: recorder.client,
    );

    await credentials.update('DEEPSEEK_API_KEY', 'ds-key');
    await pumpEventQueue();
    await provider.chat(messages);
    expect(recorder.last, 'Bearer ark-key');

    provider.close();
    credentials.close();
  });

  test('close 后不再跟随凭据变更', () async {
    final _Recorder recorder = _Recorder();
    final InMemoryCredentials credentials = InMemoryCredentials(
      initial: <String, String>{'ARK_API_KEY': 'before-close'},
    );
    final DoubaoProvider provider = DoubaoProvider(
      credentials: credentials,
      client: recorder.client,
    );

    provider.close();
    await credentials.update('ARK_API_KEY', 'after-close');
    await pumpEventQueue();
    await provider.chat(messages);
    expect(recorder.last, 'Bearer before-close');

    credentials.close();
  });

  test('显式 apiKey 优先于凭据服务', () async {
    final _Recorder recorder = _Recorder();
    final InMemoryCredentials credentials = InMemoryCredentials(
      initial: <String, String>{'ARK_API_KEY': 'from-store'},
    );
    final DoubaoProvider provider = DoubaoProvider(
      apiKey: 'explicit-key',
      credentials: credentials,
      client: recorder.client,
    );

    await provider.chat(messages);
    expect(recorder.last, 'Bearer explicit-key');

    provider.close();
    credentials.close();
  });

  test('deepseek 用自己的凭据键', () async {
    final _Recorder recorder = _Recorder();
    final InMemoryCredentials credentials = InMemoryCredentials(
      initial: <String, String>{'DEEPSEEK_API_KEY': 'ds-store'},
    );
    final DeepSeekProvider provider = DeepSeekProvider(
      credentials: credentials,
      client: recorder.client,
    );

    await provider.chat(messages);
    expect(recorder.last, 'Bearer ds-store');

    provider.close();
    credentials.close();
  });

  test('不传 credentials 时回退 Platform.environment', () async {
    final String path = Platform.environment['PATH'] ?? '';
    expect(path, isNotEmpty, reason: '测试进程应设置 PATH');
    final _Recorder recorder = _Recorder();
    final DoubaoProvider provider = DoubaoProvider(
      credentialKey: 'PATH',
      client: recorder.client,
    );

    await provider.chat(messages);
    expect(recorder.last, 'Bearer $path');

    provider.close();
  });
}
