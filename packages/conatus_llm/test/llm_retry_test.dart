/// `RetryingLlm` / `RetryPolicy` / `LlmErrorKind` 的行为约束。
///
/// 退避时长靠注入的 [LlmSleeper] 与 `Random` 断言，不真的等待——否则单测
/// 会因为 500ms+ 的 sleep 变得很慢，而且退避序列的断言本身也不该依赖时钟。
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:conatus_llm/conatus_llm.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import 'builtin_provider_helpers.dart';

/// 记录每次睡眠时长的假 sleeper。
class _Sleeper {
  final List<Duration> waits = <Duration>[];

  Future<void> call(Duration duration) async => waits.add(duration);
}

/// 按脚本逐次失败的替身：每次调用 `actions` 里的一个动作。
class _ScriptedProvider implements LlmProvider {
  _ScriptedProvider(this.name, this.actions);

  @override
  final String name;
  final List<Future<LlmResult> Function()> actions;
  int calls = 0;

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) {
    final Future<LlmResult> Function() action = _next();
    calls++;
    return action();
  }

  @override
  Stream<LlmStreamEvent> chatStream(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async* {
    final Future<LlmResult> Function() action = _next();
    calls++;
    final LlmResult result = await action();
    yield LlmTextDelta(result.content);
  }

  /// 脚本用尽后停在最后一个动作上。
  Future<LlmResult> Function() _next() {
    final int index = calls < actions.length ? calls : actions.length - 1;
    return actions[index];
  }

  @override
  void close() {}
}

Future<LlmResult> Function() _boom(LlmException error) => () async => throw error;

LlmResult _ok(String content) =>
    LlmResult(content: content, provider: 'p', model: 'm');

LlmException _rateLimited({int status = 429, Duration? after}) =>
    LlmException('p', 'slow down', statusCode: status, retryAfter: after);

void main() {
  group('LlmErrorKind', () {
    test('按状态码推断类别', () {
      expect(LlmErrorKind.infer(401), LlmErrorKind.auth);
      expect(LlmErrorKind.infer(403), LlmErrorKind.auth);
      expect(LlmErrorKind.infer(429), LlmErrorKind.rateLimit);
      expect(LlmErrorKind.infer(529), LlmErrorKind.rateLimit);
      expect(LlmErrorKind.infer(400), LlmErrorKind.badRequest);
      expect(LlmErrorKind.infer(404), LlmErrorKind.badRequest);
      expect(LlmErrorKind.infer(500), LlmErrorKind.server);
      expect(LlmErrorKind.infer(503), LlmErrorKind.server);
    });

    test('无状态码按传输层失败处理（可重试）', () {
      expect(LlmErrorKind.infer(null), LlmErrorKind.network);
      expect(LlmErrorKind.infer(null).isRetryable, isTrue);
    });

    test('只有限流 / 服务端 / 网络值得重试', () {
      const retryable = <LlmErrorKind>{
        LlmErrorKind.rateLimit,
        LlmErrorKind.server,
        LlmErrorKind.network,
      };
      for (final LlmErrorKind kind in LlmErrorKind.values) {
        expect(kind.isRetryable, retryable.contains(kind), reason: kind.name);
      }
    });

    test('显式标注的类别优先于状态码推断', () {
      const LlmException config = LlmException('p', '缺少 API Key',
          kind: LlmErrorKind.config);
      expect(config.errorKind, LlmErrorKind.config);
      expect(config.isRetryable, isFalse);
    });

    test('未标注时按状态码推断', () {
      const LlmException rateLimited = LlmException('p', 'busy', statusCode: 429);
      expect(rateLimited.errorKind, LlmErrorKind.rateLimit);
      expect(rateLimited.isRetryable, isTrue);
    });
  });

  group('isRetryableError', () {
    test('限流 / 5xx / 传输异常可重试', () {
      expect(isRetryableError(_rateLimited()), isTrue);
      expect(
        isRetryableError(const LlmException('p', 'oops', statusCode: 500)),
        isTrue,
      );
      expect(isRetryableError(TimeoutException('slow')), isTrue);
      expect(isRetryableError(StateError('编程错误')), isFalse);
    });

    test('401 / 400 / 缺 Key 不重试', () {
      for (final int status in <int>[400, 401, 403, 404]) {
        expect(
          isRetryableError(LlmException('p', 'no', statusCode: status)),
          isFalse,
          reason: '$status',
        );
      }
      expect(
        isRetryableError(const LlmException('p', 'no key',
            kind: LlmErrorKind.config)),
        isFalse,
      );
    });
  });

  group('RetryPolicy.delayFor', () {
    test('指数翻倍：500ms → 1s → 2s → 4s', () {
      const RetryPolicy policy = RetryPolicy(jitter: 0);
      expect(policy.delayFor(1).inMilliseconds, 500);
      expect(policy.delayFor(2).inMilliseconds, 1000);
      expect(policy.delayFor(3).inMilliseconds, 2000);
      expect(policy.delayFor(4).inMilliseconds, 4000);
    });

    test('受 maxDelay 封顶', () {
      const RetryPolicy policy = RetryPolicy(
        baseDelay: Duration(seconds: 1),
        maxDelay: Duration(seconds: 3),
        jitter: 0,
      );
      expect(policy.delayFor(5).inSeconds, 3);
    });

    test('服务端给了 Retry-After 就照它等，不叠加抖动', () {
      const RetryPolicy policy = RetryPolicy();
      expect(
        policy.delayFor(1, retryAfter: const Duration(seconds: 7)),
        const Duration(seconds: 7),
      );
    });

    test('Retry-After 超过上限时仍被封顶', () {
      const RetryPolicy policy = RetryPolicy(
        maxDelay: Duration(seconds: 5),
        jitter: 0,
      );
      expect(
        policy.delayFor(1, retryAfter: const Duration(minutes: 5)),
        const Duration(seconds: 5),
      );
    });

    test('抖动落在 ±jitter 区间内且不为负', () {
      const RetryPolicy policy = RetryPolicy();
      final Random random = Random(7);
      for (int i = 0; i < 50; i++) {
        final Duration delay = policy.delayFor(1, random: random);
        expect(delay.inMilliseconds, inInclusiveRange(375, 625));
      }
    });
  });

  group('RetryingLlm 非流式', () {
    test('429 重试到成功，中途按退避等待', () async {
      final _Sleeper sleeper = _Sleeper();
      final _ScriptedProvider inner = _ScriptedProvider('p', <Future<LlmResult> Function()>[
        _boom(_rateLimited()),
        _boom(const LlmException('p', 'boom', statusCode: 503)),
        () async => _ok('成功'),
      ]);
      final RetryingLlm llm = RetryingLlm(
        inner,
        policy: const RetryPolicy(jitter: 0),
        sleep: sleeper.call,
      );

      final LlmResult result =
          await llm.chat(<LlmMessage>[const LlmMessage('user', 'hi')]);

      expect(result.content, '成功');
      expect(inner.calls, 3);
      expect(sleeper.waits.map((Duration d) => d.inMilliseconds),
          <int>[500, 1000]);
    });

    test('401 不重试：换 Key 无意义的失败直接上抛', () async {
      final _Sleeper sleeper = _Sleeper();
      final _ScriptedProvider inner = _ScriptedProvider('p', <Future<LlmResult> Function()>[
        _boom(const LlmException('p', 'unauthorized', statusCode: 401)),
      ]);
      final RetryingLlm llm = RetryingLlm(inner, sleep: sleeper.call);

      await expectLater(
        llm.chat(<LlmMessage>[const LlmMessage('user', 'hi')]),
        throwsA(isA<LlmException>()),
      );
      expect(inner.calls, 1, reason: '认证失败不应重试');
      expect(sleeper.waits, isEmpty);
    });

    test('次数用尽后上抛最后一次的错误', () async {
      final _Sleeper sleeper = _Sleeper();
      final _ScriptedProvider inner = _ScriptedProvider('p', <Future<LlmResult> Function()>[
        _boom(const LlmException('p', 'boom', statusCode: 500)),
      ]);
      final RetryingLlm llm = RetryingLlm(
        inner,
        policy: const RetryPolicy(maxAttempts: 3, jitter: 0),
        sleep: sleeper.call,
      );

      await expectLater(
        llm.chat(<LlmMessage>[const LlmMessage('user', 'hi')]),
        throwsA(isA<LlmException>()
            .having((LlmException e) => e.message, 'message', 'boom')),
      );
      expect(inner.calls, 3);
      expect(sleeper.waits, hasLength(2), reason: '3 次尝试 = 2 次等待');
    });

    test('RetryPolicy.none 只试一次', () async {
      final _Sleeper sleeper = _Sleeper();
      final _ScriptedProvider inner = _ScriptedProvider('p', <Future<LlmResult> Function()>[
        _boom(const LlmException('p', 'boom', statusCode: 500)),
      ]);
      final RetryingLlm llm = RetryingLlm(
        inner,
        policy: RetryPolicy.none,
        sleep: sleeper.call,
      );

      await expectLater(
        llm.chat(<LlmMessage>[const LlmMessage('user', 'hi')]),
        throwsA(isA<LlmException>()),
      );
      expect(inner.calls, 1);
    });

    test('onRetry 通报尝试序号与等待时长', () async {
      final _Sleeper sleeper = _Sleeper();
      final List<LlmRetryAttempt> seen = <LlmRetryAttempt>[];
      final _ScriptedProvider inner = _ScriptedProvider('p', <Future<LlmResult> Function()>[
        _boom(_rateLimited(after: const Duration(seconds: 3))),
        () async => _ok('ok'),
      ]);
      final RetryingLlm llm = RetryingLlm(
        inner,
        policy: const RetryPolicy(jitter: 0),
        sleep: sleeper.call,
        onRetry: seen.add,
      );

      await llm.chat(<LlmMessage>[const LlmMessage('user', 'hi')]);

      expect(seen, hasLength(1));
      expect(seen.single.provider, 'p');
      expect(seen.single.attempt, 2);
      expect(seen.single.maxAttempts, 4);
      expect(seen.single.delay, const Duration(seconds: 3));
      expect(seen.single.honoredRetryAfter, isTrue);
      expect(seen.single.summary, contains('触发限流'));
    });

    test('透传 name 与 close', () async {
      final _ScriptedProvider inner = _ScriptedProvider('my-provider', <Future<LlmResult> Function()>[
        () async => _ok('x'),
      ]);
      var closed = false;
      final RetryingLlm llm = RetryingLlm(
        _ClosableProvider(inner, () => closed = true),
        sleep: (_) async {},
      );

      expect(llm.name, 'my-provider');
      llm.close();
      expect(closed, isTrue);
    });
  });

  group('RetryingLlm 流式', () {
    test('尚未产出任何事件时可重试', () async {
      final _Sleeper sleeper = _Sleeper();
      final _ScriptedProvider inner = _ScriptedProvider('p', <Future<LlmResult> Function()>[
        _boom(const LlmException('p', 'boom', statusCode: 502)),
        () async => _ok('重试后成功'),
      ]);
      final RetryingLlm llm = RetryingLlm(
        inner,
        policy: const RetryPolicy(jitter: 0),
        sleep: sleeper.call,
      );

      final List<LlmStreamEvent> events = await llm
          .chatStream(<LlmMessage>[const LlmMessage('user', 'hi')]).toList();

      expect(events.whereType<LlmTextDelta>().single.text, '重试后成功');
      expect(inner.calls, 2);
      expect(sleeper.waits, hasLength(1));
    });

    test('已经产出增量后失败：直接上抛，不静默重来', () async {
      final _Sleeper sleeper = _Sleeper();
      final llm = RetryingLlm(
        _HalfStreamThenFailProvider(),
        policy: const RetryPolicy(jitter: 0),
        sleep: sleeper.call,
      );

      await expectLater(
        llm.chatStream(<LlmMessage>[const LlmMessage('user', 'hi')]).toList(),
        throwsA(isA<LlmException>()),
      );
      expect(sleeper.waits, isEmpty, reason: '已吐过增量，重试会产生重复内容');
    });
  });

  group('重试 + 回退串联', () {
    test('先在主提供商退避重试，仍失败才回退到备选', () async {
      final _Sleeper primarySleeper = _Sleeper();
      final _Sleeper backupSleeper = _Sleeper();
      final List<String> events = <String>[];
      final _ScriptedProvider primary =
          _ScriptedProvider('主', <Future<LlmResult> Function()>[
        _boom(const LlmException('主', 'boom', statusCode: 500)),
      ]);
      final _ScriptedProvider backup =
          _ScriptedProvider('备', <Future<LlmResult> Function()>[
        () async => _ok('备选答'),
      ]);
      final FallbackLlm chain = FallbackLlm(
        <LlmProvider>[
          RetryingLlm(primary,
              policy: const RetryPolicy(maxAttempts: 2, jitter: 0),
              sleep: primarySleeper.call,
              onRetry: (LlmRetryAttempt a) => events.add('retry:${a.provider}')),
          RetryingLlm(backup,
              policy: const RetryPolicy(maxAttempts: 2, jitter: 0),
              sleep: backupSleeper.call),
        ],
        onFallback: (LlmFallbackEvent e) => events.add('fallback:${e.fromProvider}'
            '->${e.toProvider}'),
      );

      final LlmResult result =
          await chain.chat(<LlmMessage>[const LlmMessage('user', 'hi')]);

      expect(result.content, '备选答');
      expect(primary.calls, 2, reason: '主提供商先自己重试一次');
      expect(primarySleeper.waits, hasLength(1));
      expect(backupSleeper.waits, isEmpty, reason: '备选一次成功，不必等');
      expect(events, <String>['retry:主', 'fallback:主->备']);
    });

    test('备选也全失败时汇总每个提供商的错误', () async {
      final FallbackLlm chain = FallbackLlm(
        <LlmProvider>[
          _ScriptedProvider('主', <Future<LlmResult> Function()>[
            _boom(const LlmException('主', 'a', statusCode: 500)),
          ]),
          _ScriptedProvider('备', <Future<LlmResult> Function()>[
            _boom(const LlmException('备', 'b', statusCode: 429)),
          ]),
        ],
      );

      await expectLater(
        chain.chat(<LlmMessage>[const LlmMessage('user', 'hi')]),
        throwsA(isA<LlmException>().having(
          (LlmException e) => e.message,
          'message',
          allOf(contains('主: a'), contains('备: b')),
        )),
      );
    });
  });

  group('parseRetryAfter', () {
    test('delta-seconds', () {
      expect(parseRetryAfter('30'), const Duration(seconds: 30));
    });

    test('非法 / 负数 / 缺失都返回 null', () {
      expect(parseRetryAfter(null), isNull);
      expect(parseRetryAfter(''), isNull);
      expect(parseRetryAfter('soon'), isNull);
      expect(parseRetryAfter('-5'), isNull);
    });

    test('HTTP-date：未来的时间给出正差值', () {
      final String header = HttpDate.format(
          DateTime.now().toUtc().add(const Duration(seconds: 20)));
      final Duration? parsed = parseRetryAfter(header);
      expect(parsed, isNotNull);
      expect(parsed!.inSeconds, inInclusiveRange(15, 20));
    });

    test('HTTP-date：过去的时间返回 null', () {
      final String header = HttpDate.format(
          DateTime.now().toUtc().subtract(const Duration(minutes: 5)));
      expect(parseRetryAfter(header), isNull);
    });
  });

  group('wire 层错误分类', () {
    test('非 200 响应按状态码分类并带上 Retry-After', () async {
      var attempts = 0;
      final provider = doubaoProviderForTest(
        apiKey: 'k',
        client: MockClient((_) async {
          attempts++;
          if (attempts == 1) {
            return http.Response('{"error":{"message":"rate limited"}}', 429,
                headers: <String, String>{'retry-after': '2'});
          }
          return http.Response(
            'data: {"choices":[{"delta":{"content":"ok"},"finish_reason":"stop"}]}\n\n'
            'data: [DONE]\n\n',
            200,
            headers: <String, String>{
              'content-type': 'text/event-stream; charset=utf-8',
            },
          );
        }),
      );
      final _Sleeper sleeper = _Sleeper();
      final RetryingLlm llm = RetryingLlm(
        provider,
        policy: const RetryPolicy(jitter: 0),
        sleep: sleeper.call,
      );

      final LlmResult result =
          await llm.chat(<LlmMessage>[const LlmMessage('user', 'hi')]);

      expect(result.content, 'ok');
      expect(sleeper.waits, <Duration>[const Duration(seconds: 2)],
          reason: '照服务端说的等 2s');
    });

    test('错误正文取结构化 error.message，不吐整段 body', () async {
      final provider = doubaoProviderForTest(
        apiKey: 'k',
        client: MockClient((_) async => http.Response(
              '{"error":{"message":"context length exceeded","type":"x"}}',
              400,
            )),
      );

      await expectLater(
        provider.chat(<LlmMessage>[const LlmMessage('user', 'hi')]),
        throwsA(isA<LlmException>()
            .having((LlmException e) => e.message, 'message',
                'context length exceeded')
            .having((LlmException e) => e.errorKind, 'errorKind',
                LlmErrorKind.badRequest)),
      );
    });

    test('缺 Key 归类为 config：重试无意义', () async {
      final provider = doubaoProviderForTest(apiKey: '');
      await expectLater(
        provider.chat(<LlmMessage>[const LlmMessage('user', 'hi')]),
        throwsA(isA<LlmException>()
            .having((LlmException e) => e.errorKind, 'errorKind',
                LlmErrorKind.config)),
      );
    });
  });
}

/// 记录 `close()` 调用的包装器。
class _ClosableProvider implements LlmProvider {
  _ClosableProvider(this.inner, this.onClose);

  final LlmProvider inner;
  final void Function() onClose;

  @override
  String get name => inner.name;

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) =>
      inner.chat(messages, options: options, tools: tools);

  @override
  Stream<LlmStreamEvent> chatStream(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) =>
      inner.chatStream(messages, options: options, tools: tools);

  @override
  void close() => onClose();
}

/// 先吐一段增量再失败的流：用来验证「已产出就不重试」。
class _HalfStreamThenFailProvider implements LlmProvider {
  @override
  String get name => 'half';

  @override
  Future<LlmResult> chat(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async =>
      _ok('unused');

  @override
  Stream<LlmStreamEvent> chatStream(
    List<LlmMessage> messages, {
    Map<String, dynamic>? options,
    List<Map<String, dynamic>>? tools,
  }) async* {
    yield const LlmTextDelta('半句');
    throw const LlmException('half', 'boom', statusCode: 500);
  }

  @override
  void close() {}
}
